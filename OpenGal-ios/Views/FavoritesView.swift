import SwiftUI

struct FavoritesView: View {
    @ObservedObject var store: ConversationStore
    @ObservedObject private var tts = TTSService.shared

    var body: some View {
        let favorites = store.allFavorites
        List {
            if favorites.isEmpty {
                ContentUnavailableView("暂无收藏", systemImage: "star",
                    description: Text("在对话中点击 ★ 收藏消息"))
            } else {
                ForEach(favorites) { msg in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(msg.content)
                            .font(.body)
                        HStack {
                            Text(msg.timestamp, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Spacer()
                            if msg.savedAudioFilename != nil {
                                Button(action: {
                                    if tts.playingMessageId == msg.id {
                                        tts.stopCurrent()
                                    } else {
                                        tts.playFavorite(messageId: msg.id)
                                    }
                                }) {
                                    Image(systemName: tts.playingMessageId == msg.id
                                          ? "stop.circle.fill" : "play.circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(tts.playingMessageId == msg.id ? .red : .accentColor)
                                }
                                .buttonStyle(.plain)
                            }
                            Button(action: { store.unfavorite(messageId: msg.id) }) {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("收藏夹")
        .navigationBarTitleDisplayMode(.inline)
    }
}
