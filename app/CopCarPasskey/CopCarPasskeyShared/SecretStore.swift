import Foundation
import Security

/// Thread-safe read/write of the 32-byte shared secret in the iOS Keychain.
enum SecretStore {
    static func save(_ secret: Data) throws {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        KeychainKeys.sharedSecret,
            kSecValueData:          secret,
            // AfterFirstUnlock (not ThisDeviceOnly) is required for iCloud Keychain sync
            kSecAttrAccessible:     kSecAttrAccessibleAfterFirstUnlock,
            kSecAttrSynchronizable: kCFBooleanTrue!
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        KeychainKeys.sharedSecret,
            kSecAttrSynchronizable: kCFBooleanTrue!,
            kSecReturnData:         true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete() {
        let query: [CFString: Any] = [
            kSecClass:              kSecClassGenericPassword,
            kSecAttrAccount:        KeychainKeys.sharedSecret,
            kSecAttrSynchronizable: kCFBooleanTrue!
        ]
        SecItemDelete(query as CFDictionary)
    }

    enum KeychainError: Error {
        case saveFailed(OSStatus)
    }
}
