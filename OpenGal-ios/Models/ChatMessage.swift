import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

// Attachment carried with a user message
struct MessageAttachment: Identifiable, Equatable, Codable {
    let id: UUID
    let filename: String
    let mimeType: String
    // base64-encoded content for API transmission
    let base64Data: String

    init(id: UUID = UUID(), filename: String, mimeType: String, base64Data: String) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.base64Data = base64Data
    }

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isPDF: Bool { mimeType == "application/pdf" }
}

struct ChatMessage: Identifiable, Equatable, Codable {
    let id: UUID
    var role: MessageRole
    var content: String
    var attachments: [MessageAttachment]
    var timestamp: Date
    var isFavorited: Bool
    var savedAudioFilename: String?
    var isStreaming: Bool

    init(id: UUID = UUID(), role: MessageRole, content: String,
         attachments: [MessageAttachment] = [],
         timestamp: Date = Date(), isFavorited: Bool = false,
         savedAudioFilename: String? = nil, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
        self.isFavorited = isFavorited
        self.savedAudioFilename = savedAudioFilename
        self.isStreaming = isStreaming
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content, attachments, timestamp, isFavorited, savedAudioFilename, isStreaming
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        role = try c.decode(MessageRole.self, forKey: .role)
        content = try c.decode(String.self, forKey: .content)
        attachments = (try? c.decode([MessageAttachment].self, forKey: .attachments)) ?? []
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        isFavorited = (try? c.decode(Bool.self, forKey: .isFavorited)) ?? false
        savedAudioFilename = try? c.decode(String.self, forKey: .savedAudioFilename)
        isStreaming = (try? c.decode(Bool.self, forKey: .isStreaming)) ?? false
    }
}

enum ConversationMode: String, Codable {
    case unset    = "unset"
    case gal      = "gal"
    case default_ = "default"   // stored as "default" on disk
}

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var mode: ConversationMode
    var createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]

    init(id: UUID = UUID(), title: String = "新对话", mode: ConversationMode = .unset,
         createdAt: Date = Date(), updatedAt: Date = Date(), messages: [ChatMessage] = []) {
        self.id = id
        self.title = title
        self.mode = mode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    enum CodingKeys: String, CodingKey {
        case id, title, mode, createdAt, updatedAt, messages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        messages = try c.decode([ChatMessage].self, forKey: .messages)
        // mode may be absent in conversations saved before this field was added
        if let m = try c.decodeIfPresent(ConversationMode.self, forKey: .mode) {
            mode = m
        } else {
            // Old conversation with messages → treat as default mode, not unset
            mode = messages.isEmpty ? .unset : .default_
        }
    }
}

// MARK: - API wire types

struct TTSConfig: Sendable {
    let enabled: Bool
    let baseURL: String
}

// Content block for multimodal messages
enum APIContentBlock: Codable {
    case text(String)
    case image(mediaType: String, data: String)      // base64 image
    case document(mediaType: String, data: String)   // base64 PDF

    enum CodingKeys: String, CodingKey {
        case type, text, source
    }
    struct Source: Codable {
        let type: String
        let media_type: String
        let data: String
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t):
            try c.encode("text", forKey: .type)
            try c.encode(t, forKey: .text)
        case .image(let mt, let d):
            try c.encode("image", forKey: .type)
            try c.encode(Source(type: "base64", media_type: mt, data: d), forKey: .source)
        case .document(let mt, let d):
            try c.encode("document", forKey: .type)
            try c.encode(Source(type: "base64", media_type: mt, data: d), forKey: .source)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type_ = try c.decode(String.self, forKey: .type)
        switch type_ {
        case "image":
            let src = try c.decode(Source.self, forKey: .source)
            self = .image(mediaType: src.media_type, data: src.data)
        case "document":
            let src = try c.decode(Source.self, forKey: .source)
            self = .document(mediaType: src.media_type, data: src.data)
        default:
            let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            self = .text(text)
        }
    }
}

struct APIMessage: Codable {
    let role: String
    // content can be a plain string (text-only) or array of blocks (multimodal)
    let contentBlocks: [APIContentBlock]

    enum CodingKeys: String, CodingKey { case role, content }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        // If single text block, send as plain string for back-compat
        if contentBlocks.count == 1, case .text(let t) = contentBlocks[0] {
            try c.encode(t, forKey: .content)
        } else {
            try c.encode(contentBlocks, forKey: .content)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        role = try c.decode(String.self, forKey: .role)
        if let text = try? c.decode(String.self, forKey: .content) {
            contentBlocks = [.text(text)]
        } else {
            contentBlocks = (try? c.decode([APIContentBlock].self, forKey: .content)) ?? []
        }
    }

    init(role: String, text: String) {
        self.role = role
        self.contentBlocks = [.text(text)]
    }

    init(role: String, blocks: [APIContentBlock]) {
        self.role = role
        self.contentBlocks = blocks
    }
}

struct ThinkingConfig: Codable {
    let type: String        // "enabled"
    let budget_tokens: Int
}

struct ChatRequest: Codable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [APIMessage]
    let thinking: ThinkingConfig?
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, max_tokens, system, messages, thinking, stream
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(model, forKey: .model)
        try c.encode(max_tokens, forKey: .max_tokens)
        try c.encodeIfPresent(system, forKey: .system)
        try c.encode(messages, forKey: .messages)
        try c.encodeIfPresent(thinking, forKey: .thinking)
        try c.encode(stream, forKey: .stream)
    }
}

struct ChatResponse: Codable {
    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
    let content: [ContentBlock]
}
