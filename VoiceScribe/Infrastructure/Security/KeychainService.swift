import Foundation
import Security

/// Secure storage for sensitive credentials using macOS Keychain.
///
/// Replaces @AppStorage (UserDefaults plist) for API keys and other secrets.
/// UserDefaults stores data in an unencrypted plist readable by any process
/// running as the same user. Keychain encrypts at rest and requires
/// authorization for access.
final class KeychainService {

    static let shared = KeychainService()

    private let service = "com.voicescribe.credentials"

    // MARK: - Public API

    /// Save a string value securely in the Keychain.
    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete existing item first (update = delete + add)
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve a string value from the Keychain.
    func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the Keychain.
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Migrate an existing value from UserDefaults to Keychain.
    /// Returns true if a migration occurred.
    @discardableResult
    func migrateFromUserDefaults(key: String, userDefaultsKey: String? = nil) -> Bool {
        let udKey = userDefaultsKey ?? key
        guard let value = UserDefaults.standard.string(forKey: udKey),
              !value.isEmpty else { return false }

        // Only migrate if Keychain doesn't already have a value
        guard get(forKey: key) == nil else { return false }

        let saved = set(value, forKey: key)
        if saved {
            // Clear the insecure copy
            UserDefaults.standard.removeObject(forKey: udKey)
        }
        return saved
    }
}
