import SwiftUI

struct DirectoryBrowserView: View {
    let server: SSHServer
    @State var currentPath: String

    @State private var entries: [RemoteFileEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var resolvedPath: String = ""

    private let ssh = SSHConnectionManager.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载目录…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(err).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding()
                    Button("重试") { Task { await loadDirectory() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fileList
            }
        }
        .navigationTitle(pathTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: SessionListView(server: server, projectPath: resolvedPath)) {
                    HStack(spacing: 4) {
                        Text("选择").font(.body)
                        Image(systemName: "checkmark.circle")
                    }
                }
                .disabled(resolvedPath.isEmpty)
            }
        }
        .task { await loadDirectory() }
    }

    private var pathTitle: String {
        let p = resolvedPath.isEmpty ? currentPath : resolvedPath
        if p == "/" { return "/" }
        return URL(fileURLWithPath: p).lastPathComponent
    }

    private var fileList: some View {
        List {
            // Parent directory row
            if canGoUp {
                NavigationLink(destination: DirectoryBrowserView(
                    server: server,
                    currentPath: parentPath)) {
                    Label("..", systemImage: "arrow.up.circle")
                        .foregroundStyle(.blue)
                }
            }

            // Directories
            ForEach(entries.filter { $0.isDirectory }) { entry in
                NavigationLink(destination: DirectoryBrowserView(
                    server: server,
                    currentPath: ((resolvedPath.isEmpty ? currentPath : resolvedPath) + "/" + entry.name)
                        .replacingOccurrences(of: "//", with: "/"))) {
                    Label(entry.name, systemImage: "folder.fill")
                        .foregroundStyle(.primary)
                }
            }

            // Files (shown dimmed — not navigable but informative)
            if !entries.filter({ !$0.isDirectory }).isEmpty {
                Section("文件") {
                    ForEach(entries.filter { !$0.isDirectory }) { entry in
                        Label(entry.name, systemImage: "doc")
                            .foregroundStyle(.secondary)
                            .font(.body)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var canGoUp: Bool {
        let p = resolvedPath.isEmpty ? currentPath : resolvedPath
        return p != "/" && !p.isEmpty
    }

    private var parentPath: String {
        let p = resolvedPath.isEmpty ? currentPath : resolvedPath
        let url = URL(fileURLWithPath: p)
        return url.deletingLastPathComponent().path
    }

    private func loadDirectory() async {
        isLoading = true
        errorMessage = nil
        do {
            let expanded = try await ssh.expandPath(currentPath, on: server)
            resolvedPath = expanded
            entries = try await ssh.listDirectory(expanded, on: server)
            entries.sort { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name < b.name
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
