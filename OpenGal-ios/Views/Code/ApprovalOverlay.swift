import SwiftUI

struct ApprovalOverlay: View {
    let prompt: ApprovalPrompt
    var onSelect: (ApprovalOption) -> Void
    var onInterrupt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 16, weight: .semibold))
                Text(prompt.question)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, prompt.command.isEmpty && prompt.description.isEmpty ? 12 : 8)

            // Command block
            if !prompt.command.isEmpty {
                Text(prompt.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            // Description
            if !prompt.description.isEmpty {
                Text(prompt.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider().padding(.horizontal, 8)

            // Options
            ForEach(prompt.options) { option in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(option)
                }) {
                    HStack {
                        Text(option.label)
                            .font(.system(.body))
                            .foregroundStyle(option.isDestructive ? .red : .primary)
                        Spacer()
                        if !option.isDestructive {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if option.id < prompt.options.count {
                    Divider().padding(.horizontal, 8)
                }
            }

            Divider().padding(.horizontal, 8)

            // Interrupt button
            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onInterrupt()
            }) {
                HStack {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 14))
                    Text("中断")
                        .font(.system(.body))
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 8)
        .padding(.horizontal, 24)
    }
}
