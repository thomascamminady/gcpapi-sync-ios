import Foundation
import Security

/// Generic passwords in this device's Keychain.
///
/// Items are readable after the first unlock (so background refreshes can work) and never
/// leave the device: they are excluded from iCloud Keychain and from backups.
nonisolated struct KeychainStore: Sendable {
    /// The Keychain service all items of this app are stored under.
    let service: String

    /// The app's store.
    static let standard = Self(service: "dev.camminady.gcpapi-sync")

    private func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// The item stored for `account`, or `nil` if there is none.
    func data(for account: String) throws(KeychainError) -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    /// Store `data` for `account`, replacing what was there.
    func set(_ data: Data, for account: String) throws(KeychainError) {
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query(account)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Delete the item for `account`, if there is one.
    func remove(_ account: String) throws(KeychainError) {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

/// A Keychain operation failed.
nonisolated struct KeychainError: Error, Equatable {
    /// The Security framework's status code.
    let status: OSStatus
}
