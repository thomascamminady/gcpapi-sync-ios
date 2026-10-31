import Foundation
import Security

/// Generic passwords in this device's Keychain.
///
/// Items are readable after the first unlock (so background refreshes can work) and never
/// leave the device: they are excluded from iCloud Keychain and from backups. A Mac build signed
/// without a provisioning profile keeps them in the login keychain instead, which it may use.
nonisolated struct KeychainStore: Sendable {
    /// The Keychain service all items of this app are stored under.
    let service: String

    /// The app's store.
    static let standard = Self(service: "dev.camminady.gcpapi-sync")

    private func query(_ account: String, dataProtection: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtection,
        ]
    }

    /// Whether to try the login keychain after `status` from the data protection keychain: an
    /// app signed without a provisioning profile (a Mac build made outside Xcode) may not use
    /// the latter.
    static func fallsBack(after status: OSStatus) -> Bool {
        status == errSecMissingEntitlement
    }

    /// `operation` on the data protection keychain, or on the login keychain where the app may
    /// not use the former.
    private func onKeychain(_ operation: (_ dataProtection: Bool) -> OSStatus) -> OSStatus {
        let status = operation(true)
        return Self.fallsBack(after: status) ? operation(false) : status
    }

    /// The item stored for `account`, or `nil` if there is none.
    func data(for account: String) throws(KeychainError) -> Data? {
        var result: CFTypeRef?
        let status = onKeychain { dataProtection in
            var query = query(account, dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            return SecItemCopyMatching(query as CFDictionary, &result)
        }
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    /// Store `data` for `account`, replacing what was there.
    func set(_ data: Data, for account: String) throws(KeychainError) {
        let status = onKeychain { dataProtection in
            let update = [kSecValueData as String: data]
            let query = query(account, dataProtection: dataProtection)
            var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData as String] = data
                if dataProtection {
                    item[kSecAttrAccessible as String] =
                        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                }
                status = SecItemAdd(item as CFDictionary, nil)
            }
            return status
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Delete the item for `account`, if there is one.
    func remove(_ account: String) throws(KeychainError) {
        let status = onKeychain { dataProtection in
            SecItemDelete(query(account, dataProtection: dataProtection) as CFDictionary)
        }
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
