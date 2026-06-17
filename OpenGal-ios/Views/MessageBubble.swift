import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    var showPlayButton: Bool = true
    var onPlay: () -> Void
    var onFavorite: () -> Void

    @ObservedObject private var tts = TTSService.shared

    private var isUser: Bool { message.role == .user }
    private var isPlaying: Bool { tts.playingMessageId == message.id }

    var body: some View {
        if isUser {
            userBubble
        } else {
            assistantContent
        }
    }

    // MARK: - User: right-aligned grey pill

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 6) {
                // Attachment previews
                if !message.attachments.isEmpty {
                    ForEach(message.attachments) { att in
                        attachmentPreview(att)
                    }
                }
                if !message.content.isEmpty {
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func attachmentPreview(_ att: MessageAttachment) -> some View {
        if att.isImage, let data = Data(base64Encoded: att.base64Data),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 200, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            HStack(spacing: 6) {
                Image(systemName: att.isPDF ? "doc.fill" : "doc")
                    .foregroundStyle(.secondary)
                Text(att.filename)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Assistant: full-width text + action row

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            MarkdownView(text: message.content)
                .textSelection(.enabled)

            // Action row — hidden while streaming
            if !message.isStreaming {
                HStack(spacing: 16) {
                    if showPlayButton {
                        actionButton(
                            icon: isPlaying ? "stop.fill" : "speaker.wave.2",
                            color: isPlaying ? .red : .secondary,
                            action: onPlay
                        )
                    }
                    actionButton(
                        icon: message.isFavorited ? "star.fill" : "star",
                        color: message.isFavorited ? .yellow : .secondary,
                        action: onFavorite
                    )
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}
