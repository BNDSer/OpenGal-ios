import Foundation

struct ApprovalPrompt {
    let question: String       // e.g. "Allow this bash command?"
    let command: String        // the command/tool being requested
    let description: String    // optional description line
    let options: [ApprovalOption]
}

struct ApprovalOption: Identifiable {
    let id: Int
    let label: String          // e.g. "Yes", "No", "Yes, allow for all projects"
    let isDestructive: Bool
}

struct DiffBlock: Identifiable {
    let id = UUID()
    let filename: String
    let lines: [DiffLine]
}

struct DiffLine: Identifiable {
    let id = UUID()
    enum Kind { case header, added, removed, context }
    let kind: Kind
    let text: String
}

struct ParsedOutput {
    var displayText: String
    var approvalPrompt: ApprovalPrompt?
    var diffBlocks: [DiffBlock]
    var isStreaming: Bool
    var needsEsc: Bool      // true when TUI shows "Esc to cancel/exit/close"
}

enum ClaudeOutputParser {
    private static let spinnerChars = CharacterSet(charactersIn: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏")

    // Parse full capture-pane output.
    // anchorAfterLine: the last line of the user's input prompt (❯ <user text>),
    // so we only look at content after that anchor.
    static func parse(_ raw: String, anchorAfterLine anchor: String? = nil) -> ParsedOutput {
        let clean = ANSIStripper.strip(raw)
        var lines = clean.components(separatedBy: "\n")

        // If we have an anchor, drop everything up to and including it
        if let anchor = anchor, !anchor.isEmpty {
            // Find the last occurrence of the anchor line (user prompt line)
            if let idx = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasSuffix(anchor) &&
                ($0.trimmingCharacters(in: .whitespaces).hasPrefix("❯") || $0.trimmingCharacters(in: .whitespaces).hasPrefix("> ")) }) {
                lines = Array(lines.dropFirst(idx + 1))
            }
        }

        var result = ParsedOutput(displayText: "", approvalPrompt: nil, diffBlocks: [], isStreaming: false, needsEsc: false)

        // Detect spinner → still generating
        let tail = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.suffix(4)
        result.isStreaming = tail.contains { line in
            line.unicodeScalars.contains { spinnerChars.contains($0) }
        }

        // Detect approval prompt — scan for ❯ Yes / No selection UI
        result.approvalPrompt = detectApprovalPrompt(from: lines)

        // Detect Esc-dismissable UI: /cost, /status, /doctor output, resume picker etc.
        result.needsEsc = lines.suffix(8).contains { line in
            let t = line.lowercased()
            return t.contains("esc to cancel") || t.contains("esc to exit") ||
                   t.contains("esc to close") || t.contains("· esc") ||
                   t.contains("escape to") || t.contains("ctrl+c to cancel")
        }

        // Extract diffs
        result.diffBlocks = extractDiffs(from: lines)

        // Build display text: everything after the anchor that isn't pure TUI chrome
        result.displayText = extractDisplayText(from: lines)

        return result
    }

    // Detect Claude Code's approval prompt UI:
    // ❯ Yes               (selected option)
    //   Yes, and don't ask again
    //   No
    static func detectApprovalPrompt(from lines: [String]) -> ApprovalPrompt? {
        // Find the ❯ Yes line
        guard let yesIdx = lines.indices.first(where: {
            let t = lines[$0].trimmingCharacters(in: .whitespaces)
            return (t.hasPrefix("❯") || t.hasPrefix("●")) && t.lowercased().contains("yes")
        }) else { return nil }

        // Collect option lines around the Yes line (up to 6 lines window)
        var options: [ApprovalOption] = []
        let start = max(0, yesIdx - 1)
        let end = min(lines.count - 1, yesIdx + 5)
        var optionId = 1
        for i in start...end {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let isSelected = t.hasPrefix("❯") || t.hasPrefix("●")
            let label: String
            if isSelected {
                label = String(t.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if t.hasPrefix(" ") || (!t.hasPrefix("─") && !t.hasPrefix("│") && !t.hasPrefix("?")) {
                // Unselected option lines are indented or plain
                label = t
            } else {
                continue
            }
            guard !label.isEmpty,
                  !label.hasPrefix("─"),
                  !label.hasPrefix("│"),
                  label.count < 80 else { continue }
            let isNo = label.lowercased().hasPrefix("no")
            options.append(ApprovalOption(id: optionId, label: label, isDestructive: isNo))
            optionId += 1
        }
        guard !options.isEmpty else { return nil }

        // Find question: scan up from yesIdx for a "?" line or tool description
        var question = ""
        var command = ""
        var description = ""
        for i in stride(from: yesIdx - 1, through: max(0, yesIdx - 15), by: -1) {
            let t = lines[i].trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if isHeaderFooter(t) || isBoxLine(t) { continue }
            // Tool/command line often starts with ⚡ or is a code block
            if t.hasPrefix("⚡") || t.hasPrefix("$") || t.hasPrefix(">") {
                command = t
            } else if t.hasSuffix("?") || t.lowercased().contains("allow") || t.lowercased().contains("run") {
                question = t
            } else if description.isEmpty && !t.hasPrefix("❯") {
                description = t
            }
            if !question.isEmpty && !command.isEmpty { break }
        }
        if question.isEmpty { question = "Claude Code 请求执行操作" }

        return ApprovalPrompt(question: question, command: command,
                              description: description, options: options)
    }

    // Extract readable content from lines — keeps ● replies, tool calls, status, removes box chrome
    static func extractDisplayText(from lines: [String]) -> String {
        var out: [String] = []
        var skipUntilEmpty = false  // skip separator blocks

        for line in lines {
            let stripped = ANSIStripper.strip(line)
            let t = stripped.trimmingCharacters(in: .whitespaces)

            // Pure box-drawing separator lines
            if isBoxLine(t) {
                skipUntilEmpty = false
                continue
            }
            // TUI header/footer blocks
            if isHeaderFooter(t) {
                skipUntilEmpty = true
                continue
            }
            if skipUntilEmpty {
                if t.isEmpty { skipUntilEmpty = false }
                continue
            }

            // ● assistant reply — keep, strip the bullet
            if t.hasPrefix("● ") {
                out.append(String(t.dropFirst(2)))
                continue
            }
            if t == "●" { continue }

            // ✻ / ⏺ tool/status lines — keep as italic-style indicator
            if t.hasPrefix("✻ ") {
                out.append("_" + String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) + "_")
                continue
            }
            if t.hasPrefix("⏺ ") || t.hasPrefix("✔ ") || t.hasPrefix("✓ ") {
                out.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }

            // ❯ prompt line — stop, this marks end of assistant turn
            if t.hasPrefix("❯") || t == "?" || t.hasPrefix("? for") {
                break
            }

            // Footer hint lines
            if t.hasPrefix("?") || t.contains("for shortcuts") { continue }

            // Normal content lines (continuation of ● block, tool output, etc.)
            if !t.isEmpty {
                out.append(t)
            } else if !out.isEmpty && out.last != "" {
                out.append("")
            }
        }

        // Trim trailing blank lines
        while out.last == "" { out.removeLast() }
        return out.joined(separator: "\n")
    }

    private static func isBoxLine(_ t: String) -> Bool {
        guard !t.isEmpty else { return false }
        let boxSet = CharacterSet(charactersIn: "─│╭╮╰╯├┤┬┴┼▔▁▏▕ ")
        return t.unicodeScalars.allSatisfy { boxSet.contains($0) }
    }

    private static func isHeaderFooter(_ t: String) -> Bool {
        guard !t.isEmpty else { return false }
        // Lines that are part of the startup box
        if t.contains("Claude Code v") { return true }
        if t.contains("Tips for getting started") { return true }
        if t.contains("Welcome back!") { return true }
        if t.contains("What's new") { return true }
        if t.contains("/release-notes") { return true }
        if t.contains("Run /init") { return true }
        if t.contains("API Usage Billing") { return true }
        if t.contains("MCP servers failed") { return true }
        // Path-only lines (working directory display)
        let pathPattern = t.hasPrefix("/") || (t.contains("/workspace/") || t.contains("/home/"))
        if pathPattern && !t.hasPrefix("●") && !t.hasPrefix("✻") { return true }
        return false
    }

    static func extractDiffs(from lines: [String]) -> [DiffBlock] {
        var blocks: [DiffBlock] = []
        var i = 0
        while i < lines.count {
            let l0 = lines[i].trimmingCharacters(in: .whitespaces)
            if (l0.hasPrefix("--- ") || l0.hasPrefix("---\t")),
               i + 1 < lines.count {
                let l1 = lines[i+1].trimmingCharacters(in: .whitespaces)
                if l1.hasPrefix("+++ ") || l1.hasPrefix("+++\t") {
                    let raw = String(l1.dropFirst(4))
                    let filename = raw.hasPrefix("b/") ? String(raw.dropFirst(2)) : raw
                    var diffLines: [DiffLine] = []
                    i += 2
                    while i < lines.count {
                        let l = lines[i]
                        if l.hasPrefix("@@") {
                            diffLines.append(DiffLine(kind: .header, text: l))
                        } else if l.hasPrefix("+"), !l.hasPrefix("+++") {
                            diffLines.append(DiffLine(kind: .added, text: String(l.dropFirst())))
                        } else if l.hasPrefix("-"), !l.hasPrefix("---") {
                            diffLines.append(DiffLine(kind: .removed, text: String(l.dropFirst())))
                        } else if l.hasPrefix(" ") {
                            diffLines.append(DiffLine(kind: .context, text: String(l.dropFirst())))
                        } else { break }
                        i += 1
                    }
                    if !diffLines.isEmpty {
                        blocks.append(DiffBlock(filename: filename.trimmingCharacters(in: .whitespaces), lines: diffLines))
                    }
                    continue
                }
            }
            i += 1
        }
        return blocks
    }
}
