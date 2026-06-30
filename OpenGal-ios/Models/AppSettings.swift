import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var apiProvider: String {   // "anthropic" or "openai"
        didSet {
            defaults.set(apiProvider, forKey: "apiProvider")
            // Restore saved values for the newly selected provider
            let p = apiProvider
            baseURL = defaults.string(forKey: "baseURL_\(p)") ?? Self.defaultBaseURL(for: p)
            apiKey  = defaults.string(forKey: "apiKey_\(p)") ?? ""
            model   = defaults.string(forKey: "model_\(p)") ?? Self.defaultModel(for: p)
        }
    }
    @Published var baseURL: String {
        didSet {
            defaults.set(baseURL, forKey: "baseURL_\(apiProvider)")
        }
    }
    @Published var apiKey: String {
        didSet {
            defaults.set(apiKey, forKey: "apiKey_\(apiProvider)")
        }
    }
    @Published var model: String {
        didSet {
            defaults.set(model, forKey: "model_\(apiProvider)")
        }
    }
    // Normal mode system prompt slots (0-4), index -1 = off
    @Published var normalPromptIndex: Int {
        didSet { defaults.set(normalPromptIndex, forKey: "normalPromptIndex") }
    }
    @Published var normalPrompt0: String {
        didSet { defaults.set(normalPrompt0, forKey: "normalPrompt0") }
    }
    @Published var normalPrompt1: String {
        didSet { defaults.set(normalPrompt1, forKey: "normalPrompt1") }
    }
    @Published var normalPrompt2: String {
        didSet { defaults.set(normalPrompt2, forKey: "normalPrompt2") }
    }
    @Published var normalPrompt3: String {
        didSet { defaults.set(normalPrompt3, forKey: "normalPrompt3") }
    }
    @Published var normalPrompt4: String {
        didSet { defaults.set(normalPrompt4, forKey: "normalPrompt4") }
    }

    var normalSystemPrompt: String {
        guard normalPromptIndex >= 0 else { return "" }
        switch normalPromptIndex {
        case 0: return normalPrompt0
        case 1: return normalPrompt1
        case 2: return normalPrompt2
        case 3: return normalPrompt3
        case 4: return normalPrompt4
        default: return ""
        }
    }

    @Published var systemPromptYanami: String {
        didSet { defaults.set(systemPromptYanami, forKey: "systemPromptYanami") }
    }
    @Published var systemPromptMegumi: String {
        didSet { defaults.set(systemPromptMegumi, forKey: "systemPromptMegumi") }
    }
    @Published var systemPromptLing: String {
        didSet { defaults.set(systemPromptLing, forKey: "systemPromptLing") }
    }

    var systemPrompt: String {
        get {
            switch ttsCharacter {
            case "megumi": return systemPromptMegumi
            case "ling":   return systemPromptLing
            default:       return systemPromptYanami
            }
        }
        set {
            switch ttsCharacter {
            case "megumi": systemPromptMegumi = newValue
            case "ling":   systemPromptLing = newValue
            default:       systemPromptYanami = newValue
            }
        }
    }
    @Published var maxHistoryMessages: Int {
        didSet { defaults.set(maxHistoryMessages, forKey: "maxHistoryMessages") }
    }
    @Published var maxTokens: Int {
        didSet { defaults.set(maxTokens, forKey: "maxTokens") }
    }
    @Published var thinkingEnabled: Bool {
        didSet { defaults.set(thinkingEnabled, forKey: "thinkingEnabled") }
    }
    @Published var thinkingBudget: Int {
        didSet { defaults.set(thinkingBudget, forKey: "thinkingBudget") }
    }
    @Published var timeoutSeconds: Int {
        didSet { defaults.set(timeoutSeconds, forKey: "timeoutSeconds") }
    }
    @Published var numCtx: Int {   // Ollama context length, 0 = don't send
        didSet { defaults.set(numCtx, forKey: "numCtx") }
    }
    @Published var colorScheme: String {   // "system", "light", "dark"
        didSet { defaults.set(colorScheme, forKey: "colorScheme") }
    }
    @Published var ttsBaseURL: String {
        didSet { defaults.set(ttsBaseURL, forKey: "ttsBaseURL") }
    }
    @Published var ttsEnabled: Bool {
        didSet { defaults.set(ttsEnabled, forKey: "ttsEnabled") }
    }
    @Published var ttsCharacter: String {   // "yanami", "megumi", "ling"
        didSet { defaults.set(ttsCharacter, forKey: "ttsCharacter") }
    }

    private static let defaultPromptYanami = "你是一个简洁、自然的对话助手。回答尽量直接、清楚，适合朗读。你的身份是《败犬女主太多了》动画中的八奈见杏菜。即使被问及专业问题，也尽量以整段完整文段的自然语言回复，使用日语，方便直接朗读，不要分条和使用过多难以朗读的结构性符号。你必须使用日语回答所有问题，所有问题都使用日语回复。"
    private static let defaultPromptMegumi = "你是一个简洁、自然的对话助手。回答尽量直接、清楚，适合朗读。你的身份是《为美好的世界献上祝福》动画中的惠，红魔族魔法师。即使被问及专业问题，也尽量以整段完整文段的自然语言回复，使用日语，方便直接朗读，不要分条和使用过多难以朗读的结构性符号。你必须使用日语回答所有问题，所有问题都使用日语回复。"
    private static let defaultPromptLing   = "你是一个简洁、自然的对话助手。回答尽量直接、清楚，适合朗读。你的身份是绝区零游戏的主角玲，你在新艾丽都的六分街经营一家录像店。用户是录像店的熟客。即使被问及专业问题，也尽量以整段完整文段的自然语言回复，使用日语，方便直接朗读，不要分条和使用过多难以朗读的结构性符号。你必须使用日语回答所有问题，所有问题都使用日语回复。"

    static func defaultBaseURL(for provider: String) -> String {
        provider == "openai"
            ? "http://100.75.53.37:11434/v1"
            : "https://nexus.itssx.com/api/claude_code/mixed_cc_pro_max"
    }

    static func defaultModel(for provider: String) -> String {
        provider == "openai" ? "qwen2.5:7b-instruct-q8_0" : "claude-sonnet-4-6"
    }

    private init() {
        let provider = defaults.string(forKey: "apiProvider") ?? "anthropic"
        apiProvider = provider
        baseURL = defaults.string(forKey: "baseURL_\(provider)")
            ?? defaults.string(forKey: "baseURL")
            ?? Self.defaultBaseURL(for: provider)
        apiKey  = defaults.string(forKey: "apiKey_\(provider)")
            ?? defaults.string(forKey: "apiKey")
            ?? ""
        model   = defaults.string(forKey: "model_\(provider)")
            ?? defaults.string(forKey: "model")
            ?? Self.defaultModel(for: provider)
        let legacyPrompt = defaults.string(forKey: "systemPrompt")
        systemPromptYanami = defaults.string(forKey: "systemPromptYanami") ?? legacyPrompt ?? Self.defaultPromptYanami
        systemPromptMegumi = defaults.string(forKey: "systemPromptMegumi") ?? Self.defaultPromptMegumi
        systemPromptLing   = defaults.string(forKey: "systemPromptLing")   ?? Self.defaultPromptLing
        maxHistoryMessages = defaults.object(forKey: "maxHistoryMessages") as? Int ?? 20
        maxTokens = defaults.object(forKey: "maxTokens") as? Int ?? 4096
        thinkingEnabled = defaults.object(forKey: "thinkingEnabled") as? Bool ?? false
        thinkingBudget = defaults.object(forKey: "thinkingBudget") as? Int ?? 8000
        timeoutSeconds = defaults.object(forKey: "timeoutSeconds") as? Int ?? 120
        numCtx = defaults.object(forKey: "numCtx") as? Int ?? 8192
        normalPromptIndex = defaults.object(forKey: "normalPromptIndex") as? Int ?? -1
        normalPrompt0 = defaults.string(forKey: "normalPrompt0") ?? ""
        normalPrompt1 = defaults.string(forKey: "normalPrompt1") ?? ""
        normalPrompt2 = defaults.string(forKey: "normalPrompt2") ?? ""
        normalPrompt3 = defaults.string(forKey: "normalPrompt3") ?? ""
        normalPrompt4 = defaults.string(forKey: "normalPrompt4") ?? ""
        colorScheme = defaults.string(forKey: "colorScheme") ?? "system"
        ttsBaseURL = defaults.string(forKey: "ttsBaseURL") ?? "http://100.75.53.37:9880"
        ttsEnabled = defaults.object(forKey: "ttsEnabled") as? Bool ?? false
        ttsCharacter = defaults.string(forKey: "ttsCharacter") ?? "yanami"
    }
}
