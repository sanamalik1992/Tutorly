import Foundation
import Security

enum Keychain {
    private static let service = "com.tutorly.keys"

    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
        var add = q; add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(q as CFDictionary)
    }
}

extension Keychain {
    static func saveAppJwt(_ token: String) { save(token, for: "appJwt") }
    static func appJwt() -> String?         { read("appJwt") }
    static func deleteAppJwt()              { delete("appJwt") }

    /// True for DEBUG builds (Xcode runs) AND TestFlight sandbox builds, but false
    /// for production App Store builds. Used to gate the dev OpenAI-key bypass so
    /// it's available in TestFlight testing without shipping in production.
    static var allowDevBypass: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }
}
