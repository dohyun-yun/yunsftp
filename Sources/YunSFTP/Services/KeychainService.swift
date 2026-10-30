import Foundation
import Security

public final class KeychainService: @unchecked Sendable {
    public static let shared = KeychainService()
    private let serviceName = "com.finsternis.yunsftp"

    private init() {}

    private func accountKey(for connection: RemoteConnection) -> String {
        return "\(connection.id.uuidString)_\(connection.username)@\(connection.host):\(connection.port)"
    }

    public func savePassword(_ password: String, for connection: RemoteConnection) {
        guard !password.isEmpty else { return }
        let account = accountKey(for: connection)
        let data = password.data(using: .utf8) ?? Data()

        // Delete existing item if present
        deletePassword(for: connection)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    public func loadPassword(for connection: RemoteConnection) -> String? {
        let account = accountKey(for: connection)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, let pwd = String(data: data, encoding: .utf8) {
            return pwd
        }
        return nil
    }

    public func deletePassword(for connection: RemoteConnection) {
        let account = accountKey(for: connection)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
