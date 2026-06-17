import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var attachments: [MessageAttachment]
    var isLoading: Bool
    var isDisabled: Bool = false
    var onSend: () -> Void
    var onCancel: () -> Void
    var onAttach: () -> Void

    @FocusState var focused: Bool

    private var canSend: Bool {
        !isLoading && !isDisabled && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Attachment chips above the pill
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { att in attachmentChip(att) }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                }
            }

            // Single pill: [+] [text field] [send]
            ZStack(alignment: .leading) {
                // Glass pill background
                HStack(alignment: .bottom, spacing: 0) {
                    Color.clear.frame(width: 44, height: 50)
                    TextField(isDisabled ? "请先选择对话模式" : "询问 OpenGal", text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(1...6)
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .disabled(isDisabled)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onEnded { v in
                                    if v.translation.height > 15 {
                                        UIApplication.shared.sendAction(
                                            #selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
                                    } else if v.translation.height < -15 && !focused {
                                        focused = true
                                    }
                                }
                        )
                        .onSubmit { if canSend { onSend() } }
                        .submitLabel(.send)
                    Color.clear.frame(width: 44, height: 50)
                }
                .frame(minHeight: 50)
                .glassEffect(.regular.interactive(), in: Capsule())

                // Buttons sit above glass layer — always pinned to bottom
                HStack(alignment: .bottom, spacing: 0) {
                    Button(action: { UIImpactFeedbackGenerator(style: .light).impactOccurred(); onAttach() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if isLoading { onCancel() } else { onSend() }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isLoading ? Color.primary : (canSend ? Color.primary : Color(.systemGray4)))
                                .frame(width: 30, height: 30)
                            if isLoading {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemBackground))
                                    .frame(width: 11, height: 11)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color(.systemBackground))
                            }
                        }
                        .frame(width: 44, height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isLoading && !canSend)
                    .animation(.spring(duration: 0.2), value: isLoading)
                }
                .frame(height: 50)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 6)
    }

    private func attachmentChip(_ att: MessageAttachment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: att.isImage ? "photo" : "doc")
                .font(.caption)
            Text(att.filename).font(.caption).lineLimit(1)
            Button { attachments.removeAll { $0.id == att.id } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .clipShape(Capsule())
    }
}
