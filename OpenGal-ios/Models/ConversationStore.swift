import Foundation
import Combine

@MainActor
final class ConversationStore: ObservableObject {
    static let shared = ConversationStore()

    @Published var conversations: [Conversation] = []
    @Published var activeId: UUID?

    var active: Conversation? {
        get { conversations.first { $0.id == activeId } }
    }

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("conversations.json")
    }

    private init() {
        load()
        if conversations.isEmpty {
            let c = Conversation()
            conversations.append(c)
            activeId = c.id
        } else {
            activeId = conversations.first?.id
        }
    }

    // MARK: - Conversation management

    func newConversation() {
        let c = Conversation()
        conversations.insert(c, at: 0)
        activeId = c.id
        save()
    }

    func select(_ id: UUID) {
        activeId = id
    }

    func delete(_ id: UUID) {
        // Delete favorite audio files for messages in this conversation
        if let conv = conversations.first(where: { $0.id == id }) {
            for msg in conv.messages where msg.savedAudioFilename != nil {
                TTSService.shared.deleteFavoriteAudio(messageId: msg.id)
            }
        }
        conversations.removeAll { $0.id == id }
        if activeId == id {
            activeId = conversations.first?.id
            if activeId == nil {
                let c = Conversation()
                conversations.append(c)
                activeId = c.id
            }
        }
        save()
    }

    // MARK: - Message operations

    func appendMessage(_ msg: ChatMessage) {
        guard let idx = conversations.firstIndex(where: { $0.id == activeId }) else { return }
        conversations[idx].messages.append(msg)
        conversations[idx].updatedAt = Date()
        sortByRecent()
        save()
    }

    // Removes the last message if it is a user message with no assistant reply after it.
    // Called when a request is cancelled so the unanswered question goes back to the input box.
    func removeLastUserMessageIfUnanswered() {
        guard let idx = conversations.firstIndex(where: { $0.id == activeId }) else { return }
        let msgs = conversations[idx].messages
        guard let last = msgs.last, last.role == .user else { return }
        conversations[idx].messages.removeLast()
        conversations[idx].updatedAt = Date()
        save()
    }

    // Called once after the first assistant reply to set an AI-generated title
    func setTitle(_ title: String, for conversationId: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        // Only set if still the default — never overwrite a user-set or already-generated title
        guard conversations[idx].title == "新对话" else { return }
        conversations[idx].title = title
        save()
    }

    func setMode(_ mode: ConversationMode) {
        guard let idx = conversations.firstIndex(where: { $0.id == activeId }) else { return }
        conversations[idx].mode = mode
        save()
    }

    func updateMessage(_ msg: ChatMessage) {
        guard let ci = conversations.firstIndex(where: { $0.id == activeId }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == msg.id }) else { return }
        conversations[ci].messages[mi] = msg
        save()
    }

    func clearActive() {
        guard let idx = conversations.firstIndex(where: { $0.id == activeId }) else { return }
        // Remove favorite audio for cleared messages
        for msg in conversations[idx].messages where msg.savedAudioFilename != nil {
            TTSService.shared.deleteFavoriteAudio(messageId: msg.id)
        }
        conversations[idx].messages.removeAll()
        conversations[idx].updatedAt = Date()
        save()
    }

    // MARK: - Favorites

    func favorite(messageId: UUID, audioData: Data?) {
        guard let ci = conversations.firstIndex(where: { $0.id == activeId }),
              let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageId }) else { return }
        conversations[ci].messages[mi].isFavorited = true
        conversations[ci].messages[mi].savedAudioFilename = messageId.uuidString + ".wav"
        if let data = audioData {
            TTSService.shared.saveFavoriteAudio(data: data, messageId: messageId)
        }
        save()
    }

    func unfavorite(messageId: UUID) {
        for ci in conversations.indices {
            if let mi = conversations[ci].messages.firstIndex(where: { $0.id == messageId }) {
                conversations[ci].messages[mi].isFavorited = false
                conversations[ci].messages[mi].savedAudioFilename = nil
                TTSService.shared.deleteFavoriteAudio(messageId: messageId)
                save()
                return
            }
        }
    }

    var allFavorites: [ChatMessage] {
        conversations.flatMap { $0.messages }.filter { $0.isFavorited }
    }

    var allFavoritesWithMode: [(ChatMessage, ConversationMode)] {
        conversations.flatMap { conv in
            conv.messages.filter { $0.isFavorited }.map { ($0, conv.mode) }
        }
    }

    // MARK: - Persistence

    private func sortByRecent() {
        conversations.sort { $0.updatedAt > $1.updatedAt }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("ConversationStore save error: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([Conversation].self, from: data) else { return }
        conversations = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }
}
