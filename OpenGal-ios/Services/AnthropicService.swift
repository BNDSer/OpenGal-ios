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
}

final class AnthropicService: Sendable {
    static let shared = AnthropicService()
    private init() {}

    func sendMessage(
        messages: [ChatMessage],
        config: AnthropicConfig
    ) async throws -> String {
        guard !config.baseURL.isEmpty, !config.apiKey.isEmpty else {
            throw AnthropicError.missingCredentials
        }

        let urlString = config.baseURL.hasSuffix("/")
            ? config.baseURL + "v1/messages"
            : config.baseURL + "/v1/messages"

        guard let url = URL(string: urlString) else {
            throw AnthropicError.invalidURL
        }

        let historyMessages = messages.suffix(config.maxHistoryMessages)
        let apiMessages: [APIMessage] = historyMessages.map { msg in
            if msg.attachments.isEmpty {
                return APIMessage(role: msg.role.rawValue, text: msg.content)
            }
            // Build multimodal content blocks
            var blocks: [APIContentBlock] = []
            for att in msg.attachments {
                if att.isImage {
                    blocks.append(.image(mediaType: att.mimeType, data: att.base64Data))
                } else if att.isPDF {
                    blocks.append(.document(mediaType: att.mimeType, data: att.base64Data))
                }
            }
            if !msg.content.isEmpty {
                blocks.append(.text(msg.content))
            }
            return APIMessage(role: msg.role.rawValue, blocks: blocks)
        }

        let thinkingConfig: ThinkingConfig? = config.thinkingEnabled
            ? ThinkingConfig(type: "enabled", budget_tokens: config.thinkingBudget)
            : nil

        let body = ChatRequest(
            model: config.model.isEmpty ? "claude-sonnet-4-6" : config.model,
            max_tokens: config.maxTokens,
            system: config.systemPrompt.isEmpty ? nil : config.systemPrompt,
            messages: apiMessages,
            thinking: thinkingConfig
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Extended thinking requires the beta header
        if config.thinkingEnabled {
            request.setValue("interleaved-thinking-2025-05-14", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = TimeInterval(config.timeoutSeconds)

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.connectionProxyDictionary = [:]
        let session = URLSession(configuration: sessionConfig)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AnthropicError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? "(no body)"
            throw AnthropicError.httpError(http.statusCode, bodyStr)
        }

        let parsed: ChatResponse
        do {
            parsed = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            throw AnthropicError.decodingError(error)
        }

        return parsed.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined()
    }
}
