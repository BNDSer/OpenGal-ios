import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: ConversationStore
    @Binding var showFavorites: Bool
    var onNewChat: () -> Void
    var onCode: () -> Void
    var onSelect: (UUID) -> Void

    private func haptic() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("OpenGal")
                    .font(.title3.bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 16)

            List {
                Section {
                    sidebarRow(icon: "plus.bubble", label: "新建对话") { haptic(); onNewChat() }
                    sidebarRow(icon: "terminal", label: "Code", iconColor: .green) {
                        haptic(); onCode()
                    }
                    sidebarRow(icon: "star.fill", label: "收藏夹", iconColor: .yellow) {
                        haptic(); showFavorites = true
                    }
                }

                Section("历史记录") {
                    ForEach(store.conversations) { conv in
                        conversationRow(conv)
                    }
                    .onDelete { offsets in
                        haptic()
                        offsets.map { store.conversations[$0].id }.forEach { store.delete($0) }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func sidebarRow(icon: String, label: String, iconColor: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .foregroundStyle(iconColor == .accentColor ? Color.primary : iconColor)
        }
    }

    private func modeColor(_ mode: ConversationMode) -> Color {
        switch mode {
        case .gal:      return .pink
        case .default_: return .blue
        case .unset:    return .secondary
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        let isActive = conv.id == store.activeId
        return Button(action: { haptic(); onSelect(conv.id) }) {
            HStack {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(modeColor(conv.mode))
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(conv.title)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                        .fontWeight(isActive ? .semibold : .regular)
                    Text(conv.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(isActive ? Color(.systemGray6) : Color.clear)
    }
}
