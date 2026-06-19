import Foundation
import Citadel
import NIOCore

// MARK: - Remote file entry

struct RemoteFileEntry: Identifiable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
}

// MARK: - Claude mode

enum ClaudeMode: String, CaseIterable {
    case normal = "normal"
    case autoApprove = "auto"
    case plan = "plan"

    var displayName: String {
        switch self {
        case .normal:      return "Normal"
        case .autoApprove: return "Auto ⚡"
        case .plan:        return "Plan"
        }
    }
}

// MARK: - Connection manager

// Not @MainActor — Citadel/NIO run on background threads.
// All methods are async; callers bridge back to MainActor with await.
final class SSHConnectionManager {
    static let shared = SSHConnectionManager()
    private init() {}

    private var connections: [UUID: SSHClient] = [:]
    private var homeCache: [UUID: String] = [:]

    // MARK: Connect

    func connect(to server: SSHServer) async throws -> SSHClient {
        if let existing = connections[server.id] { return existing }
        let password = KeychainService.loadPassword(for: server.id) ?? ""
        let client = try await SSHClient.connect(
            host: server.host,
            port: server.port,
            authenticationMethod: .passwordBased(username: server.username, password: password),
            hostKeyValidator: .acceptAnything(),
            reconnect: .never
        )
        connections[server.id] = client
        return client
    }

    func disconnect(serverId: UUID) async {
        try? await connections[serverId]?.close()
        connections.removeValue(forKey: serverId)
        homeCache.removeValue(forKey: serverId)
    }

    // MARK: Exec

    func exec(_ command: String, on server: SSHServer) async throws -> String {
        let client = try await connect(to: server)
        // Redirect stderr to stdout so Citadel doesn't throw TTYSTDError on stderr output.
        // Citadel treats any stderr as an error; merging avoids false failures on macOS.
        let wrapped = "(\(command)) 2>&1"
        do {
            let buffer = try await client.executeCommand(wrapped)
            return String(bytes: buffer.readableBytesView, encoding: .utf8) ?? ""
        } catch let e as TTYSTDError {
            // Return stderr content as stdout so callers can decide what to do
            return String(bytes: e.message.readableBytesView, encoding: .utf8) ?? ""
        }
    }

    // MARK: Home directory

    func resolveHome(on server: SSHServer) async throws -> String {
        if let cached = homeCache[server.id] { return cached }
        let home = (try await exec("echo $HOME", on: server))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        homeCache[server.id] = home
        return home.isEmpty ? "/root" : home
    }

    func expandPath(_ path: String, on server: SSHServer) async throws -> String {
        var p = path
        if p == "~" || p.hasPrefix("~/") {
            let home = try await resolveHome(on: server)
            p = p == "~" ? home : home + "/" + String(p.dropFirst(2))
        }
        // Normalize double slashes
        while p.contains("//") { p = p.replacingOccurrences(of: "//", with: "/") }
        return p
    }

    // MARK: Directory listing

    func listDirectory(_ path: String, on server: SSHServer) async throws -> [RemoteFileEntry] {
        let expanded = try await expandPath(path, on: server)
        let raw = try await exec("ls -1Ap \"\(expanded)\" 2>/dev/null || echo ''", on: server)
        return raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "./" }
            .map { name -> RemoteFileEntry in
                let isDir = name.hasSuffix("/")
                return RemoteFileEntry(
                    name: isDir ? String(name.dropLast()) : name,
                    isDirectory: isDir
                )
            }
    }

    // MARK: Claude session files

    // Returns percent-encoded project directory names under ~/.claude/projects/
    func listClaudeProjects(on server: SSHServer) async throws -> [String] {
        let raw = try await exec(
            "ls -1 ~/.claude/projects/ 2>/dev/null || echo ''", on: server)
        return raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // Encodes a project path the same way Claude Code does
    // e.g. /media/zichen/E/workspace/rl_training → -media-zichen-E-workspace-rl-training
    // Rules: / → -, _ → -, normalize double --
    func encodeProjectPath(_ absolutePath: String) -> String {
        var path = absolutePath
        // Normalize double slashes first
        while path.contains("//") { path = path.replacingOccurrences(of: "//", with: "/") }
        guard path.hasPrefix("/") else { return path }
        // Replace / and _ with -
        path = path.replacingOccurrences(of: "/", with: "-")
        path = path.replacingOccurrences(of: "_", with: "-")
        return path
    }

    func listSessionFiles(projectPath: String, on server: SSHServer) async throws -> [ClaudeSessionFile] {
        let encoded = encodeProjectPath(projectPath)
        print("[SSH] listSessionFiles projectPath=\(projectPath) encoded=\(encoded)")
        let raw = try await exec(
            "ls -1t $(echo ~)/.claude/projects/\(encoded)/ 2>/dev/null | grep '\\.jsonl$' || echo ''",
            on: server)
        print("[SSH] listSessionFiles raw=\(raw.prefix(200))")
        let filenames = raw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(".jsonl") }

        let homeDir = (try? await resolveHome(on: server)) ?? "~"
        let projectDir = "\(homeDir)/.claude/projects/\(encoded)"

        var files: [ClaudeSessionFile] = []
        for filename in filenames {
            let fullPath = "\(projectDir)/\(filename)"
            // stat: Linux uses -c %Y, macOS uses -f %m — try both
            let statOut = (try? await exec(
                "stat -c %Y \"\(fullPath)\" 2>/dev/null || stat -f %m \"\(fullPath)\" 2>/dev/null || echo 0",
                on: server)) ?? "0"
            let ts = TimeInterval(statOut.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
            let modDate = Date(timeIntervalSince1970: ts)
            files.append(ClaudeSessionFile(filename: filename, fullPath: fullPath, modifiedAt: modDate))
        }
        return files
    }

    // Read last user message text from a Claude Code JSONL session file (matches desktop /resume display)
    func sessionPreview(filePath: String, on server: SSHServer) async throws -> String {
        // tail to get recent entries — last user message is what desktop shows
        let raw = try await exec("tail -50 \"\(filePath)\" 2>/dev/null || echo ''", on: server)
        var lastUserText = ""
        for line in raw.components(separatedBy: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            guard obj["type"] as? String == "user",
                  obj["isMeta"] as? Bool != true else { continue }
            if let msg = obj["message"] as? [String: Any] {
                let text: String
                if let content = msg["content"] as? String {
                    text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let contentArr = msg["content"] as? [[String: Any]],
                          let first = contentArr.first(where: { ($0["type"] as? String) == "text" }),
                          let t = first["text"] as? String {
                    text = t.trimmingCharacters(in: .whitespacesAndNewlines)
                } else { continue }

                // Skip system/meta content
                if text.isEmpty { continue }
                if text.hasPrefix("<local-command") || text.hasPrefix("<command-") { continue }
                if text.hasPrefix("/exit") || text.hasPrefix("/clear") || text.hasPrefix("/quit") { continue }
                if text == "\u{200B}" { continue }  // sentinel init message
                lastUserText = String(text.prefix(80))
            }
        }
        return lastUserText
    }

    // Get the most recently modified session ID for a project (used when attaching to existing session)
    func latestSessionId(projectPath: String, on server: SSHServer) async throws -> String? {
        let encoded = encodeProjectPath(projectPath)
        let raw = try await exec(
            "ls -1t $(echo ~)/.claude/projects/\(encoded)/ 2>/dev/null | grep '\\.jsonl$' | head -1",
            on: server)
        let filename = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filename.isEmpty, filename.hasSuffix(".jsonl") else { return nil }
        return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    }

    // Load full conversation history from a JSONL session file
    func loadSessionHistory(projectPath: String, sessionId: String, on server: SSHServer) async throws -> [CodeMessage] {
        let encoded = encodeProjectPath(projectPath)
        print("[SSH] loadSessionHistory sessionId=\(sessionId)")
        let raw = try await exec("cat $(echo ~)/.claude/projects/\(encoded)/\(sessionId).jsonl 2>/dev/null || echo ''", on: server)
        print("[SSH] loadSessionHistory raw length=\(raw.count)")

        var messages: [CodeMessage] = []
        for line in raw.components(separatedBy: "\n") {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type_ = obj["type"] as? String ?? ""
            guard type_ == "user" || type_ == "assistant" else { continue }
            guard obj["isMeta"] as? Bool != true else { continue }

            if type_ == "user",
               let msg = obj["message"] as? [String: Any] {
                let content = extractTextContent(from: msg["content"])
                if !content.isEmpty,
                   !content.hasPrefix("<local-command"),
                   !content.hasPrefix("<command-name>"),
                   !content.hasPrefix("<command-"),
                   content != "\u{200B}" {  // filter sentinel init message
                    messages.append(CodeMessage(role: .user, content: content))
                }
            }

            if type_ == "assistant",
               let msg = obj["message"] as? [String: Any] {
                let text = extractTextContent(from: msg["content"])
                if !text.isEmpty {
                    messages.append(CodeMessage(role: .assistant, content: text))
                }
            }
        }
        return messages
    }

    // Extract text from Claude Code content field (String or [{type:text,text:...}])
    private func extractTextContent(from content: Any?) -> String {
        if let str = content as? String { return str.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let arr = content as? [[String: Any]] {
            return arr.filter { ($0["type"] as? String) == "text" }
                      .compactMap { $0["text"] as? String }
                      .joined(separator: "\n")
                      .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    func ensureClaudeSession(projectPath: String, mode: ClaudeMode,
                              sessionFile: String?, on server: SSHServer) async throws {
        let tmuxName = "claude-code"
        let expanded = try await expandPath(projectPath, on: server)

        // Check if session already exists — if so, just attach (don't kill)
        // Only kill+rebuild when explicitly resuming a different session file
        let existing = (try? await exec("\(envPath) tmux has-session -t \(tmuxName) 2>/dev/null && echo yes || echo no", on: server))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "no"

        if existing == "yes" && sessionFile == nil {
            // Session running, no specific resume requested — just attach
            return
        }

        // Kill only if we need to start fresh or resume a specific session
        _ = try? await exec("\(envPath) tmux kill-session -t \(tmuxName) 2>/dev/null || true", on: server)

        // Find tmux: SSH exec has minimal PATH, so search common locations explicitly
        let tmuxSearch = "command -v tmux || ls /opt/homebrew/bin/tmux /usr/local/bin/tmux /usr/bin/tmux 2>/dev/null | head -1"
        let tmuxBin = ((try? await exec(tmuxSearch, on: server)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tmux = tmuxBin.isEmpty ? "/opt/homebrew/bin/tmux" : tmuxBin

        // Find claude: same approach
        let claudeSearch = "command -v claude || ls $HOME/.local/bin/claude /opt/homebrew/bin/claude /usr/local/bin/claude 2>/dev/null | head -1"
        let claudeFound = ((try? await exec(claudeSearch, on: server)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let claudeBin = claudeFound.isEmpty ? "claude" : claudeFound

        // Find login shell
        let shellFound = ((try? await exec("echo $SHELL", on: server)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let loginShell = shellFound.isEmpty ? "/bin/zsh" : shellFound

        var claudeArgs: [String] = [claudeBin]
        if mode == .autoApprove { claudeArgs.append("--dangerously-skip-permissions") }
        if let sf = sessionFile {
            claudeArgs.append("--resume \(sf)")
        }
        let claudeCmd = claudeArgs.joined(separator: " ")

        // Set PATH explicitly to cover Homebrew on macOS and ~/.local/bin on Linux
        let pathPrefix = "PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
        let createCmd = "\(tmux) new-session -d -s \(tmuxName) -c '\(expanded)' '\(loginShell) -l -c \"\(pathPrefix) \(claudeCmd)\"' || true"
        _ = try await exec(createCmd, on: server)
    }

    // MARK: - Streaming Claude call

    // Create a new cli-mode session visible in desktop /resume list.
    // Starts claude interactively via tmux (entrypoint="cli"), waits for it to write
    // the session file, then returns the new session ID.
    func createCliSession(projectPath: String, on server: SSHServer) async throws -> String? {
        let expanded = try await expandPath(projectPath, on: server)
        let encoded = encodeProjectPath(projectPath)
        let tmuxName = "claude-init-\(UInt32.random(in: 10000...99999))"

        let claudeSearch = "command -v claude || ls $HOME/.local/bin/claude /opt/homebrew/bin/claude /usr/local/bin/claude 2>/dev/null | head -1"
        let claudeFound = ((try? await exec(claudeSearch, on: server)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let claudeBin = claudeFound.isEmpty ? "claude" : claudeFound

        let shellFound = ((try? await exec("echo $SHELL", on: server)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let loginShell = shellFound.isEmpty ? "/bin/zsh" : shellFound

        // Snapshot existing session files
        let beforeRaw = (try? await exec(
            "ls -1t $(echo ~)/.claude/projects/\(encoded)/ 2>/dev/null | grep '\\.jsonl$'",
            on: server)) ?? ""
        let before = Set(beforeRaw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(".jsonl") })

        // Use envPath prefix so tmux/claude are found without hardcoding paths
        let startCmd = "\(envPath) tmux new-session -d -s \(tmuxName) -c '\(expanded)' '\(loginShell) -l -c \"\(envPath) \(claudeBin)\"'"
        _ = try? await exec(startCmd, on: server)

        // Wait for claude to start (3s), send Enter to dismiss any first-run/trust prompt
        try await Task.sleep(nanoseconds: 3_000_000_000)
        _ = try? await exec("\(envPath) tmux send-keys -t \(tmuxName) '' Enter 2>/dev/null", on: server)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Send a sentinel message so claude writes the session file with entrypoint="cli".
        // We use a zero-width space as content — it's invisible and easily filtered.
        _ = try? await exec("\(envPath) tmux send-keys -t \(tmuxName) '\u{200B}' Enter 2>/dev/null", on: server)
        try await Task.sleep(nanoseconds: 3_000_000_000)

        // Kill session — claude has written the file by now
        _ = try? await exec("\(envPath) tmux kill-session -t \(tmuxName) 2>/dev/null", on: server)

        // Find new session file (ls -1t = newest first, pick first not in before)
        let afterRaw = (try? await exec(
            "ls -1t $(echo ~)/.claude/projects/\(encoded)/ 2>/dev/null | grep '\\.jsonl$'",
            on: server)) ?? ""
        let afterOrdered = afterRaw.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasSuffix(".jsonl") }

        let newFile = afterOrdered.first(where: { !before.contains($0) }) ?? afterOrdered.first
        print("[SSH] createCliSession before=\(before.count) after=\(afterOrdered.count) newFile=\(newFile ?? "nil")")
        guard let filename = newFile else { return nil }
        return URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
    }

    enum ClaudeStreamEvent {
        case text(String)
        case sessionId(String)
        case done
    }

    // Run claude --print --output-format stream-json and stream the response back.
    // Each line of output is a JSON object from the stream-json format.
    func streamClaude(
        prompt: String,
        projectPath: String,
        sessionId: String?,
        mode: ClaudeMode,
        on server: SSHServer
    ) async throws -> AsyncThrowingStream<ClaudeStreamEvent, Error> {
        let client = try await connect(to: server)
        let expanded = try await expandPath(projectPath, on: server)

        // Find claude binary
        let claudeFound = ((try? await exec(
            "command -v claude || ls $HOME/.local/bin/claude /opt/homebrew/bin/claude /usr/local/bin/claude 2>/dev/null | head -1",
            on: server)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let claudeBin = claudeFound.isEmpty ? "claude" : claudeFound

        // Build arguments
        var args = [claudeBin, "--print", "--verbose", "--output-format", "stream-json"]
        if let sid = sessionId { args += ["--resume", sid] }
        if mode == .autoApprove { args.append("--dangerously-skip-permissions") }
        if mode == .plan { args += ["--permission-mode", "plan"] }

        // Escape prompt for shell
        let escapedPrompt = prompt.replacingOccurrences(of: "'", with: "'\\''")
        args += ["--", "'\(escapedPrompt)'"]

        let command = "cd '\(expanded)' && PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH \(args.joined(separator: " ")) < /dev/null 2>&1"
        print("[SSH] streamClaude command: \(command)")

        let rawStream = try await client.executeCommandStream(command)

        return AsyncThrowingStream { continuation in
            Task {
                var lineBuffer = ""
                var nonJsonOutput = ""
                do {
                    for try await chunk in rawStream {
                        let bytes: ByteBuffer
                        switch chunk {
                        case .stdout(let b): bytes = b
                        case .stderr(let b): bytes = b  // stderr merged via 2>&1, but handle anyway
                        }
                        guard let text = String(bytes: bytes.readableBytesView, encoding: .utf8) else { continue }
                        print("[SSH] streamClaude raw chunk: \(text.prefix(300))")
                        lineBuffer += text

                        // Process complete lines
                        while let nl = lineBuffer.firstIndex(of: "\n") {
                            let line = String(lineBuffer[lineBuffer.startIndex..<nl])
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            lineBuffer = String(lineBuffer[lineBuffer.index(after: nl)...])
                            guard !line.isEmpty else { continue }

                            if let event = parseStreamJsonLine(line) {
                                continuation.yield(event)
                            } else {
                                nonJsonOutput += line + "\n"
                            }
                        }
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    print("[SSH] streamClaude error: \(error), nonJson: \(nonJsonOutput.prefix(300))")
                    // Wrap error with any plain-text output (e.g. claude auth error messages)
                    if !nonJsonOutput.isEmpty {
                        continuation.finish(throwing: NSError(
                            domain: "ClaudeSSH", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: nonJsonOutput.trimmingCharacters(in: .whitespacesAndNewlines)]))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }

    // Parse one line of claude --output-format stream-json output
    private func parseStreamJsonLine(_ line: String) -> ClaudeStreamEvent? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let type_ = obj["type"] as? String ?? ""

        // Session ID comes in the first result object
        if type_ == "result" || type_ == "system" {
            if let sid = obj["session_id"] as? String { return .sessionId(sid) }
        }

        // Streaming text delta
        if type_ == "assistant" {
            if let msg = obj["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]] {
                let text = content
                    .filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined()
                if !text.isEmpty { return .text(text) }
            }
        }

        // Text delta format
        if type_ == "content_block_delta",
           let delta = obj["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            return .text(text)
        }

        return nil
    }

    // PATH prefix ensures tmux/claude are found on both macOS (Homebrew) and Linux
    private let envPath = "PATH=$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

    func killClaudeSession(on server: SSHServer) async {
        _ = try? await exec("\(envPath) tmux kill-session -t claude-code 2>/dev/null || true", on: server)
    }

    func capturePane(on server: SSHServer) async throws -> String {
        try await exec(
            "\(envPath) tmux capture-pane -p -S -1000 -t claude-code 2>/dev/null || echo ''",
            on: server)
    }

    func sendKeys(_ text: String, enter: Bool = true, on server: SSHServer) async throws {
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        let suffix = enter ? " Enter" : ""
        _ = try await exec(
            "\(envPath) tmux send-keys -t claude-code '\(escaped)'\(suffix) || true", on: server)
    }

    func sendRawKey(_ key: String, on server: SSHServer) async throws {
        _ = try await exec("\(envPath) tmux send-keys -t claude-code \(key) || true", on: server)
    }
}

struct ClaudeSessionFile: Identifiable {
    let id = UUID()
    let filename: String
    let fullPath: String
    var preview: String = ""
    var modifiedAt: Date = Date()

    var sessionId: String { URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent }
}
