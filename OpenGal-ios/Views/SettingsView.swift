import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    // Common model presets
    private let modelPresets = [
        "claude-sonnet-4-6",
        "claude-opus-4-5",
        "claude-haiku-4-5-20251001",
        "claude-sonnet-4-5",
    ]

    var body: some View {
        Form {
            Section("API 配置") {
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

            Section("模型") {
                LabeledContent("Model ID") {
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
                    TextEditor(text: $settings.systemPrompt)
                        .frame(minHeight: 80)
                        .font(.body)
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
                }
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
