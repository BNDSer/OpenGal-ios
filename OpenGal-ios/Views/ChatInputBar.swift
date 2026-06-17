import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var attachments: [MessageAttachment]
    var isLoading: Bool
    var onSend: () -> Void
    var onAttach: () -> Void

    @FocusState var focused: Bool

    private var canSend: Bool {
        !isLoading && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
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
                // Glass pill background — does not intercept button taps when buttons are in ZStack above
                HStack(alignment: .center, spacing: 0) {
                    Color.clear.frame(width: 44, height: 50)
                    TextField("询问 OpenGal", text: $text, axis: .vertical)
                        .focused($focused)
                        .lineLimit(1...6)
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 10).onChanged { v in
                                if v.translation.height > 30 && focused { focused = false }
                                else if v.translation.height < -30 && !focused { focused = true }
                            }
                        )
                        .onSubmit { if canSend { onSend() } }
                        .submitLabel(.send)
                    Color.clear.frame(width: 44, height: 50)
                }
                .frame(height: 50)
                .glassEffect(.regular, in: Capsule())

                // Buttons sit above glass layer
                HStack(alignment: .center, spacing: 0) {
                    Button(action: onAttach) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 50)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: onSend) {
                        ZStack {
                            Circle()
                                .fill(canSend ? Color.black : Color(.systemGray4))
                                .frame(width: 30, height: 30)
                            if isLoading {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.white)
                                    .frame(width: 11, height: 11)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 44, height: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .animation(.spring(duration: 0.2), value: canSend)
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
