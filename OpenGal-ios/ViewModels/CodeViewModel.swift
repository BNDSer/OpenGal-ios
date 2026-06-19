import Foundation
import Combine
import UIKit

// MARK: - Message model

enum CodeRole { case user, assistant }

struct CodeMessage: Identifiable {
    let id: UUID
    var role: CodeRole
    var content: String
    var isStreaming: Bool
    var diffBlocks: [DiffBlock]

    init(role: CodeRole, content: String, isStreaming: Bool = false, diffBlocks: [DiffBlock] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.diffBlocks = diffBlocks
    }
}

// MARK: - ViewModel

@MainActor
final class CodeViewModel: ObservableObject {
    @Published var messages: [CodeMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming: Bool = false
    @Published var isConnecting: Bool = false
    @Published var errorMessage: String? = nil
    @Published var approvalPrompt: ApprovalPrompt? = nil
    @Published var needsEsc: Bool = false
    @Published var showModelPicker = false
    @Published var showSessionPicker = false
    @Published var sessionFiles: [ClaudeSessionFile] = []
    @Published var mode: ClaudeMode = .normal

    let server: SSHServer
    let projectPath: String
    let isNewSession: Bool
    // The active session ID — persists across messages in the same conversation
    private(set) var sessionId: String?

    private var streamTask: Task<Void, Never>?
    private let ssh = SSHConnectionManager.shared

    init(server: SSHServer, projectPath: String, sessionFile: String? = nil, isNewSession: Bool = false) {
        self.server = server
        self.projectPath = projectPath
        self.isNewSession = isNewSession
        self.sessionId = sessionFile
    }

    // MARK: - Session lifecycle

    func startSession() {
        guard !isConnecting else { return }
        isConnecting = true
        messages = []
        Task {
            do {
                if isNewSession {
                    // Create a cli-mode session so it appears in /resume on desktop
                    print("[VM] createCliSession start")
                    let newSid = try? await ssh.createCliSession(projectPath: projectPath, on: server)
                    print("[VM] createCliSession result: \(newSid ?? "nil")")
                    sessionId = newSid
                } else {
                    if sessionId == nil {
                        sessionId = try? await ssh.latestSessionId(projectPath: projectPath, on: server)
                    }
                    if let sid = sessionId {
                        let history = try await ssh.loadSessionHistory(
                            projectPath: projectPath, sessionId: sid, on: server)
                        messages = history
                    }
                }
                isConnecting = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                isConnecting = false
                errorMessage = "连接失败: \(error.localizedDescription)"
            }
        }
    }

    func stopSession() {
        streamTask?.cancel()
        streamTask = nil
    }

    // MARK: - Send

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        inputText = ""

        let userMsg = CodeMessage(role: .user, content: text)
        messages.append(userMsg)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        streamTask?.cancel()
        streamTask = Task { await runClaude(prompt: text) }
    }

    func sendDirectCommand(_ command: String) {
        guard !isStreaming else { return }
        let userMsg = CodeMessage(role: .user, content: command)
        messages.append(userMsg)
        streamTask?.cancel()
        streamTask = Task { await runClaude(prompt: command) }
    }

    func interrupt() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let lastIdx = messages.indices.last, messages[lastIdx].role == .assistant {
            messages[lastIdx].isStreaming = false
        }
    }

    func sendEsc() { needsEsc = false }
    func approve(option: ApprovalOption) { approvalPrompt = nil }
    func approve() { approvalPrompt = nil }
    func deny() { approvalPrompt = nil }
    func switchModel(to model: String) {}
    func resumeSession(_ session: ClaudeSessionFile) {
        sessionId = session.sessionId
        startSession()
    }

    // MARK: - Core streaming call

    private func runClaude(prompt: String) async {
        isStreaming = true

        // Start or append to assistant message
        let assistantMsgId = UUID()
        messages.append(CodeMessage(
            role: .assistant, content: "", isStreaming: true))
        let idx = messages.count - 1

        do {
            let stream = try await ssh.streamClaude(
                prompt: prompt,
                projectPath: projectPath,
                sessionId: sessionId,
                mode: mode,
                on: server
            )

            var accumulatedText = ""

            for try await event in stream {
                guard !Task.isCancelled else { break }

                switch event {
                case .text(let chunk):
                    accumulatedText += chunk
                    if idx < messages.count {
                        messages[idx].content = accumulatedText
                        messages[idx].isStreaming = true
                    }

                case .sessionId(let sid):
                    // Always track the actual session ID claude is writing to.
                    // If --resume was passed with the right sid, this will be the same value.
                    // If claude created a new session (resume failed), we adopt it so
                    // subsequent messages still go to the same file.
                    sessionId = sid

                case .done:
                    break
                }
            }

            if idx < messages.count {
                messages[idx].isStreaming = false
                messages[idx].diffBlocks = ClaudeOutputParser.extractDiffs(
                    from: accumulatedText.components(separatedBy: "\n"))
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        } catch {
            if !Task.isCancelled {
                if idx < messages.count {
                    messages[idx].isStreaming = false
                    if messages[idx].content.isEmpty {
                        messages.remove(at: idx)
                    }
                }
                errorMessage = error.localizedDescription
            }
        }

        isStreaming = false
    }
}
