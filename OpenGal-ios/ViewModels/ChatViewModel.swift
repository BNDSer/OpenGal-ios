import Foundation
import Combine
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var pendingAttachments: [MessageAttachment] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // Per-message cached audio data (non-favorited, lives only in memory until played)
    private var pendingAudioData: [UUID: Data] = [:]

    let store: ConversationStore
    private let settings: AppSettings
    private let ttsService: TTSService

    var messages: [ChatMessage] { store.active?.messages ?? [] }

    init(store: ConversationStore = .shared,
         settings: AppSettings = .shared,
         ttsService: TTSService = .shared) {
        self.store = store
        self.settings = settings
        self.ttsService = ttsService
    }

    private var requestTask: Task<Void, Never>?

    // MARK: - Send

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !text.isEmpty || !attachments.isEmpty, !isLoading else { return }
        inputText = ""
        pendingAttachments = []
        errorMessage = nil
        let userMsg = ChatMessage(role: .user, content: text, attachments: attachments)
        store.appendMessage(userMsg)
        requestTask = Task { await performRequest() }
    }

    func cancelRequest() {
        guard isLoading else { return }
        requestTask?.cancel()
        requestTask = nil
        isLoading = false
        // Find the last user message (the one that triggered this request)
        if let lastUser = store.active?.messages.last(where: { $0.role == .user }) {
            inputText = lastUser.content
            store.removeLastUserMessageIfUnanswered()
        }
    }

    func addAttachment(_ attachment: MessageAttachment) {
        pendingAttachments.append(attachment)
    }

    func removeAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func sendQuickMessage(_ text: String) {
        inputText = text
        sendMessage()
    }

    // MARK: - Clear / new chat

    func clearHistory() {
        ttsService.stopCurrent()
        pendingAudioData.removeAll()
        store.clearActive()
    }

    // MARK: - TTS controls

    func playMessage(_ msg: ChatMessage) {
        guard msg.role == .assistant else { return }
        let ttsConfig = TTSConfig(enabled: settings.ttsEnabled, baseURL: settings.ttsBaseURL, character: settings.ttsCharacter)

        if msg.isFavorited {
            // Saved file on disk
            ttsService.playFavorite(messageId: msg.id)
            return
        }

        if let data = pendingAudioData[msg.id] {
            ttsService.play(data: data, messageId: msg.id, keepFile: false)
            return
        }

        // Fetch on demand
        Task {
            guard let data = await ttsService.fetchAudio(text: msg.content, config: ttsConfig) else { return }
            pendingAudioData[msg.id] = data
            ttsService.play(data: data, messageId: msg.id, keepFile: false)
        }
    }

    func stopTTS() {
        ttsService.stopCurrent()
    }

    // MARK: - Favorites

    func toggleFavorite(_ msg: ChatMessage) {
        if msg.isFavorited {
            // Stop playback before unfavoriting to avoid deleting a file that's open
            if ttsService.playingMessageId == msg.id { ttsService.stopCurrent() }
            store.unfavorite(messageId: msg.id)
        } else {
            let audioData = pendingAudioData[msg.id]
            // If currently playing, update TTSService state first so it doesn't delete the file on finish
            if ttsService.playingMessageId == msg.id, let data = audioData {
                ttsService.markCurrentAsFavorited(messageId: msg.id, data: data)
            }
            store.favorite(messageId: msg.id, audioData: audioData)
        }
    }

    // MARK: - Private

    private func performRequest() async {
        isLoading = true
        defer { isLoading = false }

        guard !Task.isCancelled else { return }

        let mode = store.active?.mode ?? .default_
        let isGal = mode == .gal

        let config = AnthropicConfig(
            baseURL: settings.baseURL,
            apiKey: settings.apiKey,
            model: settings.model,
            systemPrompt: isGal ? settings.systemPrompt : "",
            maxHistoryMessages: settings.maxHistoryMessages,
            maxTokens: settings.maxTokens,
            thinkingEnabled: settings.thinkingEnabled,
            thinkingBudget: settings.thinkingBudget,
            timeoutSeconds: settings.timeoutSeconds
        )
        let ttsConfig = TTSConfig(
            enabled: isGal && settings.ttsEnabled,
            baseURL: settings.ttsBaseURL,
            character: settings.ttsCharacter
        )
        let conversationId = store.activeId

        // Insert a placeholder message for streaming
        let assistantMsg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        store.appendMessage(assistantMsg)
        let msgId = assistantMsg.id

        do {
            var isFirstChunk = true
            var lastError: Error? = nil

            for attempt in 0..<3 {
                if attempt > 0 {
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    store.resetStreamingMessage(id: msgId)
                    isFirstChunk = true
                }
                do {
                    let reply = try await AnthropicService.shared.streamMessage(
                        messages: messages.filter { $0.id != msgId },
                        config: config,
                        onDelta: { [weak self] chunk in
                            guard let self else { return }
                            Task { @MainActor in
                                if isFirstChunk {
                                    isFirstChunk = false
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                                self.store.appendStreamingChunk(chunk, to: msgId)
                            }
                        }
                    )

                    // Success — finalize and break
                    store.finalizeStreamingMessage(id: msgId, content: reply)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()

                    if let convId = conversationId,
                       store.conversations.first(where: { $0.id == convId })?.title == "新对话",
                       messages.filter({ $0.role == .assistant && !$0.isStreaming }).count == 1 {
                        Task { await generateTitle(for: convId, config: config) }
                    }

                    if ttsConfig.enabled {
                        Task {
                            guard let data = await ttsService.fetchAudio(text: reply, config: ttsConfig) else { return }
                            pendingAudioData[msgId] = data
                            ttsService.play(data: data, messageId: msgId, keepFile: false)
                        }
                    }
                    return
                } catch {
                    if isCancellation(error) {
                        store.removeMessage(id: msgId)
                        return
                    }
                    lastError = error
                    // Retry on 503 or network errors; give up on other errors immediately
                    if !isRetryable(error) { break }
                }
            }

            // All attempts failed
            store.removeMessage(id: msgId)
            errorMessage = lastError?.localizedDescription
        } catch {
            store.removeMessage(id: msgId)
            if isCancellation(error) { return }
            errorMessage = error.localizedDescription
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        // 503 service unavailable
        if case AnthropicError.httpError(let code, _) = error, code == 503 || code == 502 || code == 529 {
            return true
        }
        // TLS / network errors
        if case AnthropicError.networkError(let inner) = error {
            let ns = inner as NSError
            if ns.domain == NSURLErrorDomain { return true }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return true }
        return false
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let u = error as? URLError, u.code == .cancelled { return true }
        if case AnthropicError.networkError(let inner) = error {
            if inner is CancellationError { return true }
            if let u = inner as? URLError, u.code == .cancelled { return true }
        }
        // NSURLErrorCancelled = -999
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        return false
    }

    private func generateTitle(for conversationId: UUID, config: AnthropicConfig) async {
        // Build a minimal prompt: ask the model to summarise the first exchange in ≤10 chars
        guard let conv = store.conversations.first(where: { $0.id == conversationId }),
              let userMsg = conv.messages.first(where: { $0.role == .user }),
              let assistantMsg = conv.messages.first(where: { $0.role == .assistant }) else { return }

        let prompt = """
        请根据下面这段对话，用不超过10个汉字生成一个简短的标题，只输出标题本身，不要加引号或多余说明。

        用户：\(userMsg.content)
        助手：\(String(assistantMsg.content.prefix(200)))
        """

        let titleConfig = AnthropicConfig(
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            model: config.model,
            systemPrompt: "",
            maxHistoryMessages: 2,
            maxTokens: 64,
            thinkingEnabled: false,
            thinkingBudget: 0,
            timeoutSeconds: 30
        )
        let titleMessages = [ChatMessage(role: .user, content: prompt)]

        guard let title = try? await AnthropicService.shared.streamMessage(
            messages: titleMessages,
            config: titleConfig,
            onDelta: { _ in }
        ) else { return }

        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")

        store.setTitle(cleaned.isEmpty ? "新对话" : cleaned, for: conversationId)
    }
}
