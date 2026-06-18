import SwiftUI

struct AddServerView: View {
    var editing: SSHServer? = nil
    var onSave: (SSHServer, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var nickname: String = ""
    @State private var host: String = ""
    @State private var portText: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""

    private var isEditing: Bool { editing != nil }
    private var isValid: Bool {
        !nickname.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        (Int(portText) != nil)
    }

    init(editing: SSHServer? = nil, onSave: @escaping (SSHServer, String) -> Void) {
        self.editing = editing
        self.onSave = onSave
        if let s = editing {
            _nickname = State(initialValue: s.nickname)
            _host     = State(initialValue: s.host)
            _portText = State(initialValue: String(s.port))
            _username = State(initialValue: s.username)
            _password = State(initialValue: KeychainService.loadPassword(for: s.id) ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器信息") {
                    LabeledContent("名称") {
                        TextField("我的服务器", text: $nickname)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("主机") {
                        TextField("192.168.1.1", text: $host)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    LabeledContent("端口") {
                        TextField("22", text: $portText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }
                }

                Section("认证") {
                    LabeledContent("用户名") {
                        TextField("root", text: $username)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    LabeledContent("密码") {
                        SecureField(isEditing ? "留空保持不变" : "••••••••", text: $password)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Text("密码通过 iOS Keychain 安全加密存储，不会明文保存到文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isEditing ? "编辑服务器" : "添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let port = Int(portText) ?? 22
                        let server = SSHServer(
                            id: editing?.id ?? UUID(),
                            nickname: nickname.trimmingCharacters(in: .whitespaces),
                            host: host.trimmingCharacters(in: .whitespaces),
                            port: port,
                            username: username.trimmingCharacters(in: .whitespaces),
                            lastDirectory: editing?.lastDirectory ?? "~",
                            createdAt: editing?.createdAt ?? Date()
                        )
                        onSave(server, password)
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }
}
