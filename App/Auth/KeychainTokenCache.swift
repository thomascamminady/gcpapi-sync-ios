import Foundation
import GCPAPISync

/// Keeps the Garmin access token in the Keychain, so the app does not exchange its API key
/// for a new token on every launch.
nonisolated struct KeychainTokenCache: TokenCache {
    /// The Keychain account holding the token.
    static let account = "access-token"

    let store: KeychainStore

    private struct Stored: Codable {
        let fingerprint: String
        let token: String
        let expiresAt: Date
    }

    /// The cached token, if it was issued for `key` and is readable.
    func load(_ key: String) -> AccessToken? {
        guard let data = try? store.data(for: Self.account),
            let stored = try? JSONDecoder().decode(Stored.self, from: data),
            stored.fingerprint == key
        else { return nil }
        return AccessToken(value: stored.token, expiresAt: stored.expiresAt)
    }

    /// Cache `token` for `key`.
    func save(_ token: AccessToken, for key: String) throws {
        let stored = Stored(fingerprint: key, token: token.value, expiresAt: token.expiresAt)
        try store.set(JSONEncoder().encode(stored), for: Self.account)
    }

    /// Forget the cached token.
    func clear() throws {
        try store.remove(Self.account)
    }
}
