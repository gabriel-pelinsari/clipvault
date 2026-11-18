import CryptoKit
import Foundation
import Security

/// Loads the history encryption key from the user's Keychain, creating it on first use.
nonisolated enum KeychainKey {
    enum Failure: Error, CustomStringConvertible {
        case keychain(OSStatus)
        case malformedKey

        var description: String {
            switch self {
            case .keychain(let status):
                let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
                return "Keychain error \(status): \(message)"
            case .malformedKey:
                return "Stored key has an unexpected size"
            }
        }
    }

    static func loadOrCreate(service: String, account: String) throws -> SymmetricKey {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        var lookup = baseQuery
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else { throw Failure.malformedKey }
            return SymmetricKey(data: data)

        case errSecItemNotFound:
            let key = SymmetricKey(size: .bits256)
            var item = baseQuery
            item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
            item[kSecAttrLabel as String] = "ClipVault history key"
            item[kSecAttrDescription as String] = "Encrypts the ClipVault clipboard history on disk"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Failure.keychain(addStatus) }
            return key

        default:
            // Anything else (locked keychain, access denied) must not create a new key:
            // that would make the existing history permanently unreadable.
            throw Failure.keychain(status)
        }
    }
}
