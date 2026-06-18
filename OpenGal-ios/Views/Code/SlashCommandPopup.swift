import SwiftUI

private let slashCommands = [
    "/model", "/compact", "/clear", "/status",
    "/cost", "/doctor", "/resume", "/exit", "/help",
]

struct SlashCommandPopup: View {
    let input: String
    var onSelect: (String) -> Void

    private var matches: [String] {
        guard input.hasPrefix("/") else { return [] }
        let q = input.lowercased()
        return slashCommands.filter { $0.hasPrefix(q) }
    }

    var body: some View {
        if !matches.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element) { idx, cmd in
                    Button(action: { onSelect(cmd) }) {
                        HStack(spacing: 10) {
                            Image(systemName: commandIcon(cmd))
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text(cmd)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(commandHint(cmd))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if idx < matches.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
        }
    }

    private func commandIcon(_ cmd: String) -> String {
        switch cmd {
        case "/model":   return "cpu"
        case "/compact": return "arrow.down.to.line"
        case "/clear":   return "trash"
        case "/status":  return "info.circle"
        case "/cost":    return "dollarsign.circle"
        case "/doctor":  return "stethoscope"
        case "/resume":  return "clock.arrow.circlepath"
        case "/exit":    return "xmark.circle"
        case "/help":    return "questionmark.circle"
        default:         return "terminal"
        }
    }

    private func commandHint(_ cmd: String) -> String {
        switch cmd {
        case "/model":   return "切换模型"
        case "/compact": return "压缩上下文"
        case "/clear":   return "清空对话"
        case "/status":  return "查看状态"
        case "/cost":    return "费用统计"
        case "/doctor":  return "诊断"
        case "/resume":  return "恢复会话"
        case "/exit":    return "退出"
        case "/help":    return "帮助"
        default:         return ""
        }
    }
}
