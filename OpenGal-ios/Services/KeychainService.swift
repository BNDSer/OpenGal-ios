import Foundation
import Security

enum KeychainService {
    private static let service = "OpenGal.SSHPassword"

    static func savePassword(_ password: String, for serverId: UUID) {
        let data = Data(password.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: serverId.uuidString,
            kSecAttrService: service,
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadPassword(for serverId: UUID) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: serverId.uuidString,
            kSecAttrService: service,
            kSecReturnData: kCFBooleanTrue as Any,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for serverId: UUID) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: serverId.uuidString,
            kSecAttrService: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
