import SwiftUI

struct FavoritesView: View {
    @ObservedObject var store: ConversationStore
    @ObservedObject private var tts = TTSService.shared
    @State private var expanded: Set<UUID> = []

    var body: some View {
        let items = store.allFavoritesWithMode
        List {
            if items.isEmpty {
                ContentUnavailableView("暂无收藏", systemImage: "star",
                    description: Text("在对话中点击 ★ 收藏消息"))
            } else {
                ForEach(items, id: \.0.id) { msg, mode in
                    FavoriteRow(
                        msg: msg,
                        isGalMode: mode == .gal,
                        isExpanded: expanded.contains(msg.id),
                        onToggle: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if expanded.contains(msg.id) {
                                expanded.remove(msg.id)
                            } else {
                                expanded.insert(msg.id)
                            }
                        },
                        onUnfavorite: { store.unfavorite(messageId: msg.id) }
                    )
                }
            }
        }
        .navigationTitle("收藏夹")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FavoriteRow: View {
    let msg: ChatMessage
    let isGalMode: Bool
    let isExpanded: Bool
    let onToggle: () -> Void
    let onUnfavorite: () -> Void

    @ObservedObject private var tts = TTSService.shared
    private let previewLines = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Content — collapsed shows limited lines, expanded shows all
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 0) {
                    if isExpanded {
                        MarkdownView(text: msg.content)
                    } else {
                        Text(msg.content)
                            .font(.body)
                            .lineLimit(previewLines)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !isExpanded {
                        Text(isExpanded ? "" : "点击展开")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
            .buttonStyle(.plain)

            // Footer
            HStack {
                Text(msg.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                // Play button only for Gal mode favorites with saved audio
                if isGalMode, msg.savedAudioFilename != nil {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if tts.playingMessageId == msg.id { tts.stopCurrent() }
                        else { tts.playFavorite(messageId: msg.id) }
                    }) {
                        Image(systemName: tts.playingMessageId == msg.id
                              ? "stop.circle.fill" : "play.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(tts.playingMessageId == msg.id ? .red : .accentColor)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onUnfavorite()
                }) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
