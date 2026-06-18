import SwiftUI

struct DiffView: View {
    let blocks: [DiffBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                VStack(alignment: .leading, spacing: 0) {
                    // File header
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(block.filename)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))

                    // Diff lines
                    ForEach(block.lines) { line in
                        diffLine(line)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
            }
        }
    }

    @ViewBuilder
    private func diffLine(_ line: DiffLine) -> some View {
        let (bg, fg, prefix): (Color, Color, String) = {
            switch line.kind {
            case .added:
                return (Color.green.opacity(0.12), Color.green, "+")
            case .removed:
                return (Color.red.opacity(0.12), Color.red, "-")
            case .header:
                return (Color.blue.opacity(0.08), Color(.secondaryLabel), "")
            case .context:
                return (Color.clear, Color(.label), " ")
            }
        }()

        HStack(alignment: .top, spacing: 0) {
            Text(prefix)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(fg)
                .frame(width: 16)
                .padding(.leading, 6)
            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 6)
        }
        .padding(.vertical, 2)
        .background(bg)
    }
}
