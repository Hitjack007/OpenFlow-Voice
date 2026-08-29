import Foundation
import Security

enum KeychainStore {
    private static let service = "com.openflowvoice.apikeys"

    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        var status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        } else {
            var item = query
            item[kSecValueData] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Log.app.error("Keychain write failed for \(key, privacy: .public): \(status)")
        }
    }

    static func load(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: kCFBooleanTrue!,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
