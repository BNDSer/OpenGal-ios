import SwiftUI

struct ModelPickerSheet: View {
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let models = [
        "claude-sonnet-4-6",
        "claude-opus-4-5",
        "claude-haiku-4-5-20251001",
        "claude-sonnet-4-5",
    ]

    var body: some View {
        NavigationStack {
            List(models, id: \.self) { model in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(model)
                    dismiss()
                }) {
                    HStack {
                        Text(model)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct SessionPickerSheet: View {
    let sessions: [ClaudeSessionFile]
    var onSelect: (ClaudeSessionFile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.largeTitle).foregroundStyle(.tertiary)
                        Text("没有历史会话").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sessions) { session in
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onSelect(session)
                            dismiss()
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.sessionId)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !session.preview.isEmpty {
                                    Text(session.preview)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("恢复会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
