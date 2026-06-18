import SwiftUI

struct ServerListView: View {
    @ObservedObject private var store = SSHServerStore.shared
    @State private var showAddServer = false
    @State private var editingServer: SSHServer? = nil

    var body: some View {
        Group {
            if store.servers.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .navigationTitle("Code")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddServer) {
            AddServerView { newServer, password in
                SSHServerStore.shared.add(newServer)
                KeychainService.savePassword(password, for: newServer.id)
                showAddServer = false
            }
        }
        .sheet(item: $editingServer) { server in
            AddServerView(editing: server) { updated, password in
                SSHServerStore.shared.update(updated)
                if !password.isEmpty {
                    KeychainService.savePassword(password, for: updated.id)
                }
                editingServer = nil
            }
        }
    }

    private var serverList: some View {
        List {
            ForEach(store.servers) { server in
                NavigationLink(destination: DirectoryBrowserView(server: server,
                                                                 currentPath: server.lastDirectory)) {
                    serverRow(server)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.delete(server.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        editingServer = server
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func serverRow(_ server: SSHServer) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.nickname).fontWeight(.medium)
                Text("\(server.username)@\(server.host):\(server.port)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("没有服务器")
                .font(.title3.bold())
            Text("添加一台 SSH 服务器，开始远程使用 Claude Code。")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("添加服务器") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showAddServer = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
