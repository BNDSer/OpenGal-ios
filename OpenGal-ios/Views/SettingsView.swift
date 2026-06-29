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
