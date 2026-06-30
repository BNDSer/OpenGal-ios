import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    private var characterPromptBinding: Binding<String> {
        switch settings.ttsCharacter {
        case "megumi": return $settings.systemPromptMegumi
        case "ling":   return $settings.systemPromptLing
        default:       return $settings.systemPromptYanami
        }
    }

    private var normalPromptBinding: Binding<String> {
        switch settings.normalPromptIndex {
        case 0: return $settings.normalPrompt0
        case 1: return $settings.normalPrompt1
        case 2: return $settings.normalPrompt2
        case 3: return $settings.normalPrompt3
        case 4: return $settings.normalPrompt4
        default: return .constant("")
        }
    }

    // Common model presets
    private let anthropicPresets = [
        "claude-sonnet-4-6",
        "claude-opus-4-5",
        "claude-haiku-4-5-20251001",
        "claude-sonnet-4-5",
    ]
    private let openaiPresets = [
        "qwen2.5:7b-instruct-q8_0",
        "hf.co/QuantFactory/Qwen2.5-7B-Instruct-Uncensored-GGUF:Q5_K_M",
        "llama3.2:latest",
    ]
    private var modelPresets: [String] {
        settings.apiProvider == "openai" ? openaiPresets : anthropicPresets
    }

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $settings.colorScheme) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                .pickerStyle(.segmented)
            }

            Section("API 配置") {
                Picker("接口格式", selection: $settings.apiProvider) {
                    Text("Anthropic").tag("anthropic")
                    Text("OpenAI").tag("openai")
                }
                .pickerStyle(.segmented)
                LabeledContent("Base URL") {
                    TextField("https://...", text: $settings.baseURL)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
                LabeledContent("API Key") {
                    SecureField("sk-...", text: $settings.apiKey)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }

            Section("模型") {                LabeledContent("Model ID") {
                    TextField("claude-sonnet-4-6", text: $settings.model)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                // Quick-select presets
                ForEach(modelPresets, id: \.self) { preset in
                    Button(action: { settings.model = preset }) {
                        HStack {
                            Text(preset).font(.footnote).foregroundStyle(.primary)
                            Spacer()
                            if settings.model == preset {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.footnote)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("推理") {
                Stepper("Max tokens: \(settings.maxTokens)",
                        value: $settings.maxTokens,
                        in: 256...32000,
                        step: 256)

                Stepper("超时时间：\(settings.timeoutSeconds) 秒",
                        value: $settings.timeoutSeconds,
                        in: 15...600,
                        step: 15)

                if settings.apiProvider == "openai" {
                    Picker("上下文长度 (num_ctx)", selection: $settings.numCtx) {
                        Text("4K").tag(4096)
                        Text("8K").tag(8192)
                        Text("16K").tag(16384)
                        Text("32K").tag(32768)
                        Text("64K").tag(65536)
                        Text("128K").tag(131072)
                    }
                }

                Toggle("Extended Thinking", isOn: Binding(
                    get: { settings.thinkingEnabled },
                    set: { enabled in
                        settings.thinkingEnabled = enabled
                        // Ensure max_tokens > budget when enabling
                        if enabled && settings.maxTokens <= settings.thinkingBudget {
                            settings.maxTokens = settings.thinkingBudget + 1000
                        }
                    }
                ))

                if settings.thinkingEnabled {
                    Stepper("Budget: \(settings.thinkingBudget) tokens",
                            value: Binding(
                                get: { settings.thinkingBudget },
                                set: { v in
                                    settings.thinkingBudget = v
                                    // Auto-bump max_tokens if needed
                                    if settings.maxTokens <= v {
                                        settings.maxTokens = v + 1000
                                    }
                                }
                            ),
                            in: 1000...32000,
                            step: 1000)
                    Text("budget_tokens 已自动确保 < max_tokens（当前 \(settings.maxTokens)）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("对话") {
                Stepper("上下文长度：\(settings.maxHistoryMessages) 条",
                        value: $settings.maxHistoryMessages,
                        in: 2...100,
                        step: 2)
            }

            Section {
                Picker("预设", selection: $settings.normalPromptIndex) {
                    Text("关闭").tag(-1)
                    Text("1").tag(0)
                    Text("2").tag(1)
                    Text("3").tag(2)
                    Text("4").tag(3)
                    Text("5").tag(4)
                }
                .pickerStyle(.segmented)
                if settings.normalPromptIndex >= 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: normalPromptBinding)
                            .frame(minHeight: 80)
                            .font(.body)
                            .id(settings.normalPromptIndex)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("普通模式 — 系统提示词")
            } footer: {
                Text(settings.normalPromptIndex < 0 ? "已关闭，不发送系统提示词" : "对所有非 Gal 对话生效，Anthropic 和 OpenAI 模式均适用")
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Prompt")
                        .font(.subheadline)
                    TextEditor(text: characterPromptBinding)
                        .frame(minHeight: 80)
                        .font(.body)
                        .id(settings.ttsCharacter)  // force re-render on character switch
                }
                .padding(.vertical, 4)
            } header: {
                Text("Gal Mode — 角色设定")
            } footer: {
                Text("仅对 Gal Mode 生效")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("启用语音合成", isOn: $settings.ttsEnabled)
                if settings.ttsEnabled {
                    LabeledContent("TTS 服务地址") {
                        TextField("http://host:9880", text: $settings.ttsBaseURL)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    Picker("角色", selection: $settings.ttsCharacter) {
                        Text("八奈見").tag("yanami")
                        Text("恵").tag("megumi")
                        Text("玲").tag("ling")
                    }
                    .pickerStyle(.segmented)                }
            } header: {
                Text("Gal Mode — 语音")
            } footer: {
                Text("仅对 Gal Mode 生效")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }
}
