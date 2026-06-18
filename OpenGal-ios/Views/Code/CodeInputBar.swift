import SwiftUI

struct CodeInputBar: View {
    @Binding var text: String
    @Binding var mode: ClaudeMode
    var isStreaming: Bool
    var onSend: () -> Void
    var onInterrupt: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 6) {
            // Mode picker — glassEffect gives it the same material as the input pill
            Picker("模式", selection: $mode) {
                ForEach(ClaudeMode.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            // Input pill
            ZStack(alignment: .leading) {
                HStack(alignment: .bottom, spacing: 0) {
                    Color.clear.frame(width: 12, height: 44)
                    TextField("发送消息给 Claude Code…", text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(1...5)
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { if canSend { onSend() } }
                        .submitLabel(.send)
                    Color.clear.frame(width: 44, height: 44)
                }
                .frame(minHeight: 44)
                .glassEffect(.regular.interactive(), in: Capsule())

                HStack(alignment: .bottom, spacing: 0) {
                    Spacer()
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isStreaming { onInterrupt() } else { onSend() }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isStreaming ? Color.primary : (canSend ? Color.primary : Color(.systemGray4)))
                                .frame(width: 30, height: 30)
                            if isStreaming {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemBackground))
                                    .frame(width: 11, height: 11)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(.systemBackground))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && !canSend)
                    .animation(.spring(duration: 0.2), value: isStreaming)
                }
                .frame(height: 44)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 20)
        .padding(.top, 6)
    }
}
