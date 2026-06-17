import Foundation
import Combine

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
        Task { await performRequest() }
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
        let ttsConfig = TTSConfig(enabled: settings.ttsEnabled, baseURL: settings.ttsBaseURL)

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
            store.unfavorite(messageId: msg.id)
        } else {
            let audioData = pendingAudioData[msg.id]
            store.favorite(messageId: msg.id, audioData: audioData)
        }
    }

    // MARK: - Private

    private func performRequest() async {
        isLoading = true
        defer { isLoading = false }

        let mode = store.active?.mode ?? .default_
        let isGal = mode == .gal

        // Gal mode uses settings system prompt + TTS; Default mode uses neither
        let config = AnthropicConfig(
            baseURL: settings.baseURL,
            apiKey: settings.apiKey,
            model: settings.model,
            systemPrompt: isGal ? settings.systemPrompt : "",
            maxHistoryMessages: settings.maxHistoryMessages,
            maxTokens: settings.maxTokens,
            thinkingEnabled: settings.thinkingEnabled,
            thinkingBudget: settings.thinkingBudget
        )
        let ttsConfig = TTSConfig(
            enabled: isGal && settings.ttsEnabled,
            baseURL: settings.ttsBaseURL
        )
        let conversationId = store.activeId

        do {
            let reply = try await AnthropicService.shared.sendMessage(
                messages: messages,
                config: config
            )
            let assistantMsg = ChatMessage(role: .assistant, content: reply)
            store.appendMessage(assistantMsg)

            // Generate title after the very first exchange (1 user + 1 assistant)
            if let convId = conversationId,
               store.conversations.first(where: { $0.id == convId })?.title == "新对话",
               messages.filter({ $0.role == .assistant }).count == 1 {
                Task { await generateTitle(for: convId, config: config) }
            }

            if ttsConfig.enabled {
                Task {
                    guard let data = await ttsService.fetchAudio(text: reply, config: ttsConfig) else { return }
                    pendingAudioData[assistantMsg.id] = data
                    ttsService.play(data: data, messageId: assistantMsg.id, keepFile: false)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
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
            thinkingBudget: 0
        )
        let titleMessages = [ChatMessage(role: .user, content: prompt)]

        guard let title = try? await AnthropicService.shared.sendMessage(
            messages: titleMessages,
            config: titleConfig
        ) else { return }

        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")

        store.setTitle(cleaned.isEmpty ? "新对话" : cleaned, for: conversationId)
    }
}
