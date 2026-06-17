import SwiftUI

struct ModePickerView: View {
    var onSelect: (ConversationMode) -> Void

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 8) {
                Text("选择对话模式")
                    .font(.title2.bold())
                Text("开始后当前对话将保持该模式")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                modeCard(
                    icon: "sparkles",
                    title: "Gal Mode",
                    description: "角色扮演\n日语语音回复",
                    color: .pink,
                    mode: .gal
                )
                modeCard(
                    icon: "bubble.left.and.bubble.right",
                    title: "Default",
                    description: "普通对话\n无语音",
                    color: .blue,
                    mode: .default_
                )
            }
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modeCard(icon: String, title: String, description: String,
                          color: Color, mode: ConversationMode) -> some View {
        Button(action: { onSelect(mode) }) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 56, height: 56)
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(color)
                }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
            .glassEffect(.regular.interactive(),
                         in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
