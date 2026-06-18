import Foundation
import Combine

struct SSHServer: Identifiable, Codable, Hashable {
    let id: UUID
    var nickname: String
    var host: String
    var port: Int
    var username: String
    var lastDirectory: String
    var createdAt: Date

    init(id: UUID = UUID(), nickname: String, host: String,
         port: Int = 22, username: String, lastDirectory: String = "~",
         createdAt: Date = Date()) {
        self.id = id
        self.nickname = nickname
        self.host = host
        self.port = port
        self.username = username
        self.lastDirectory = lastDirectory
        self.createdAt = createdAt
    }
}

@MainActor
final class SSHServerStore: ObservableObject {
    static let shared = SSHServerStore()

    @Published var servers: [SSHServer] = []

    private var saveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ssh_servers.json")
    }

    private init() { load() }

    func add(_ server: SSHServer) {
        servers.append(server)
        save()
    }

    func update(_ server: SSHServer) {
        guard let i = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[i] = server
        save()
    }

    func delete(_ id: UUID) {
        servers.removeAll { $0.id == id }
        KeychainService.deletePassword(for: id)
        save()
    }

    func updateLastDirectory(_ id: UUID, path: String) {
        guard let i = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[i].lastDirectory = path
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(servers)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("SSHServerStore save error: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([SSHServer].self, from: data) else { return }
        servers = decoded
    }
}
