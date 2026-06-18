import SwiftUI

struct SessionListView: View {
    let server: SSHServer
    let projectPath: String

    @State private var sessions: [ClaudeSessionFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    private let ssh = SSHConnectionManager.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载会话…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(err).foregroundStyle(.secondary).padding()
                    Button("重试") { Task { await loadSessions() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sessionList
            }
        }
        .navigationTitle("选择会话")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadSessions() }
    }

    private var sessionList: some View {
        List {
            Section {
                NavigationLink(destination: CodeChatView(
                    server: server,
                    projectPath: projectPath,
                    sessionFile: nil)) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("新对话").fontWeight(.medium)
                            Text("在当前目录启动新的 Claude Code 会话")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    SSHServerStore.shared.updateLastDirectory(server.id, path: projectPath)
                })
            }

            if !sessions.isEmpty {
                Section("历史会话") {
                    ForEach(sessions) { session in
                        NavigationLink(destination: CodeChatView(
                            server: server,
                            projectPath: projectPath,
                            sessionFile: session.sessionId)) {
                            sessionRow(session)
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            SSHServerStore.shared.updateLastDirectory(server.id, path: projectPath)
                        })
                    }
                }
            } else {
                Section {
                    HStack {
                        Spacer()
                        Text("暂无历史会话").foregroundStyle(.secondary).padding()
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func sessionRow(_ session: ClaudeSessionFile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                if !session.preview.isEmpty {
                    Text(session.preview)
                        .font(.body).foregroundStyle(.primary).lineLimit(2)
                } else {
                    Text(session.sessionId.prefix(16) + "…")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.primary).lineLimit(1)
                }
                Text(session.modifiedAt, style: .relative)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func loadSessions() async {
        isLoading = true
        errorMessage = nil
        do {
            var files = try await ssh.listSessionFiles(projectPath: projectPath, on: server)
            // Load previews concurrently
            await withTaskGroup(of: (Int, String).self) { group in
                for (i, file) in files.enumerated() {
                    group.addTask {
                        let preview = (try? await ssh.sessionPreview(filePath: file.fullPath, on: server)) ?? ""
                        return (i, preview)
                    }
                }
                for await (i, preview) in group {
                    files[i].preview = preview
                }
            }
            sessions = files
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
