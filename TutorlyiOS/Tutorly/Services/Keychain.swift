import Foundation
import Security

enum Keychain {
    private static let service = "com.tutorly.apikey"

    static func save(_ value: String)     { write(value, account: "anthropic") }
    static func read() -> String?         { fetch(account: "anthropic") }
    static func clear()                   { delete(account: "anthropic") }

    static func saveOpenAI(_ value: String) { write(value, account: "openai") }
    static func readOpenAI() -> String?     { fetch(account: "openai") }
    static func clearOpenAI()               { delete(account: "openai") }

    private static func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func fetch(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
