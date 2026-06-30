import Foundation

enum AnthropicError: LocalizedError {
    case invalidURL
    case missingCredentials
    case httpError(Int, String)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL"
        case .missingCredentials: return "API URL or key not configured. Please open Settings."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .decodingError(let e): return "Failed to parse response: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        }
    }
}

struct AnthropicConfig: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String
    let systemPrompt: String
    let maxHistoryMessages: Int
    let maxTokens: Int
    let thinkingEnabled: Bool
    let thinkingBudget: Int
    let timeoutSeconds: Int
    let provider: String   // "anthropic" or "openai"
    let numCtx: Int        // Ollama num_ctx, 0 = omit
}

final class AnthropicService: Sendable {
    static let shared = AnthropicService()
    private init() {}

    /// Stream a response, calling `onDelta` for each text chunk, returning full text when done.
    func streamMessage(
        messages: [ChatMessage],
        config: AnthropicConfig,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        if config.provider == "openai" {
            return try await streamOpenAI(messages: messages, config: config, onDelta: onDelta)
        }
        return try await streamAnthropic(messages: messages, config: config, onDelta: onDelta)
    }

    // MARK: - Anthropic format

    private func streamAnthropic(
        messages: [ChatMessage],
        config: AnthropicConfig,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard !config.baseURL.isEmpty, !config.apiKey.isEmpty else {
            throw AnthropicError.missingCredentials
        }

        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        let urlString: String
        if base.hasSuffix("/v1") {
            urlString = base + "/messages"
        } else {
            urlString = base + "/v1/messages"
        }

        guard let url = URL(string: urlString) else {
            throw AnthropicError.invalidURL
        }

        let apiMessages = buildAPIMessages(messages: messages, config: config)

        let thinkingConfig: ThinkingConfig? = config.thinkingEnabled
            ? ThinkingConfig(type: "enabled", budget_tokens: config.thinkingBudget)
            : nil

        // stream: true added to request body
        let body = ChatRequest(
            model: config.model.isEmpty ? "claude-sonnet-4-6" : config.model,
            max_tokens: config.maxTokens,
            system: config.systemPrompt.isEmpty ? nil : config.systemPrompt,
            messages: apiMessages,
            thinking: thinkingConfig,
            stream: true
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if config.thinkingEnabled {
            request.setValue("interleaved-thinking-2025-05-14", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = TimeInterval(config.timeoutSeconds)

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.connectionProxyDictionary = [:]
        let session = URLSession(configuration: sessionConfig)

        let (stream, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (stream, response) = try await session.bytes(for: request)
        } catch {
            throw AnthropicError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // Read error body
            var errorBody = ""
            for try await line in stream.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            throw AnthropicError.httpError(http.statusCode, errorBody)
        }

        var fullText = ""
        var firstChunk = true

        for try await line in stream.lines {
            try Task.checkCancellation()

            // SSE format: "data: {...}" or "data: [DONE]"
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]" else { break }
            guard let data = jsonStr.data(using: .utf8) else { continue }

            // Parse the SSE event
            if let event = try? JSONDecoder().decode(SSEEvent.self, from: data) {
                if event.type == "content_block_delta",
                   let delta = event.delta,
                   delta.type == "text_delta",
                   let text = delta.text,
                   !text.isEmpty {
                    if firstChunk {
                        firstChunk = false
                    }
                    fullText += text
                    onDelta(text)
                }
            }
        }

        return fullText
    }

    private func buildAPIMessages(messages: [ChatMessage], config: AnthropicConfig) -> [APIMessage] {
        let historyMessages = messages.suffix(config.maxHistoryMessages)
        return historyMessages.map { msg in
            if msg.attachments.isEmpty {
                return APIMessage(role: msg.role.rawValue, text: msg.content)
            }
            var blocks: [APIContentBlock] = []
            for att in msg.attachments {
                if att.isImage {
                    blocks.append(.image(mediaType: att.mimeType, data: att.base64Data))
                } else if att.isPDF {
                    blocks.append(.document(mediaType: att.mimeType, data: att.base64Data))
                }
            }
            if !msg.content.isEmpty { blocks.append(.text(msg.content)) }
            return APIMessage(role: msg.role.rawValue, blocks: blocks)
        }
    }

    // MARK: - OpenAI format

    private func streamOpenAI(
        messages: [ChatMessage],
        config: AnthropicConfig,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard !config.baseURL.isEmpty, !config.apiKey.isEmpty else {
            throw AnthropicError.missingCredentials
        }

        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        // If base already ends with /v1, append /chat/completions directly
        // Otherwise append /v1/chat/completions
        let urlString: String
        if base.hasSuffix("/v1") {
            urlString = base + "/chat/completions"
        } else {
            urlString = base + "/v1/chat/completions"
        }
        guard let url = URL(string: urlString) else { throw AnthropicError.invalidURL }

        let history = messages.suffix(config.maxHistoryMessages)
        var oaiMessages: [[String: Any]] = []
        if !config.systemPrompt.isEmpty {
            oaiMessages.append(["role": "system", "content": config.systemPrompt])
        }
        for msg in history {
            if msg.attachments.isEmpty {
                oaiMessages.append(["role": msg.role.rawValue, "content": msg.content])
            } else {
                var parts: [[String: Any]] = []
                for att in msg.attachments where att.isImage {
                    parts.append(["type": "image_url",
                                  "image_url": ["url": "data:\(att.mimeType);base64,\(att.base64Data)"]])
                }
                if !msg.content.isEmpty {
                    parts.append(["type": "text", "text": msg.content])
                }
                oaiMessages.append(["role": msg.role.rawValue, "content": parts])
            }
        }

        var body: [String: Any] = [
            "model": config.model.isEmpty ? "qwen2.5:7b-instruct-q8_0" : config.model,
            "messages": oaiMessages,
            "max_tokens": config.maxTokens,
            "stream": true
        ]
        if config.numCtx > 0 {
            body["options"] = ["num_ctx": config.numCtx]
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = TimeInterval(config.timeoutSeconds)

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.connectionProxyDictionary = [:]
        let session = URLSession(configuration: sessionConfig)

        let (stream, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (stream, response) = try await session.bytes(for: request)
        } catch {
            throw AnthropicError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var errorBody = ""
            for try await line in stream.lines {
                errorBody += line
                if errorBody.count > 500 { break }
            }
            throw AnthropicError.httpError(http.statusCode, errorBody)
        }

        var fullText = ""
        for try await line in stream.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]" else { break }
            guard let data = jsonStr.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String,
                  !text.isEmpty else { continue }
            fullText += text
            onDelta(text)
        }
        return fullText
    }
}

// MARK: - SSE event types

private struct SSEEvent: Decodable {
    let type: String
    let delta: SSEDelta?
}

private struct SSEDelta: Decodable {
    let type: String
    let text: String?
}
