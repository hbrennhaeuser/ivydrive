import Foundation
import Security

struct Credentials: Codable {
    var username: String
    var password: String
}

enum KeychainHelper {
    private static let service = "MenuBarFS"

    @discardableResult
    static func save(_ credentials: Credentials, for driveId: UUID) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: driveId.uuidString
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    static func load(for driveId: UUID) -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: driveId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    static func delete(for driveId: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: driveId.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
