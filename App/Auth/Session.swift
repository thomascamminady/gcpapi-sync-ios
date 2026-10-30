import Foundation
import GCPAPISync
import Observation

/// Whether the person is connected to Garmin, and the client to use when they are.
@Observable
final class Session {
    enum State {
        case signedOut
        case signedIn(GarminClient)
    }

    /// The Keychain account holding the Personal API key.
    nonisolated static let keyAccount = "personal-api-key"

    private(set) var state: State = .signedOut
    /// Whether the session shows sample data instead of a Garmin account's.
    private(set) var isDemo = false
    private let keychain: KeychainStore
    private let transport: (any HTTPTransport)?
    /// Where data loaded from Garmin is saved; `nil` keeps nothing.
    let snapshots: SnapshotStore?
    let recordings: RecordingCache?

    /// A session that restores a previously stored key.
    ///
    /// - Parameters:
    ///   - keychain: Where the key and the access token are kept.
    ///   - transport: How requests are sent; `nil` for the network.
    ///   - snapshots: Where data loaded from Garmin is saved; `nil` keeps nothing.
    ///   - recordings: Where activity recordings are cached; `nil` keeps nothing.
    init(
        keychain: KeychainStore = .standard, transport: (any HTTPTransport)? = nil,
        snapshots: SnapshotStore? = nil, recordings: RecordingCache? = nil
    ) {
        self.keychain = keychain
        self.transport = transport
        self.snapshots = snapshots
        self.recordings = recordings
        if let data = try? keychain.data(for: Self.keyAccount),
            let key = String(data: data, encoding: .utf8),
            let client = try? makeClient(key)
        {
            state = .signedIn(client)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { true } else { false }
    }

    private func makeClient(_ apiKey: String) throws -> GarminClient {
        try Self.client(apiKey: apiKey, keychain: keychain, transport: transport)
    }

    /// A client for `apiKey` whose access tokens are kept in `keychain`.
    nonisolated static func client(
        apiKey: String, keychain: KeychainStore, transport: (any HTTPTransport)? = nil
    ) throws -> GarminClient {
        try GarminClient(
            apiKey: apiKey,
            tokenCache: KeychainTokenCache(store: keychain),
            transport: transport,
            // Configuration comes from this app, never from the process environment.
            environment: ProcessEnvironment(variables: [:], homeDirectory: .temporaryDirectory)
        )
    }

    /// A client for the key stored in `keychain`, if there is one; for background refresh.
    nonisolated static func storedClient(keychain: KeychainStore = .standard) -> GarminClient? {
        guard let data = try? keychain.data(for: keyAccount),
            let key = String(data: data, encoding: .utf8)
        else { return nil }
        return try? client(apiKey: key, keychain: keychain)
    }

    /// Check `apiKey` with Garmin and, if it works, remember it.
    func connect(apiKey: String) async throws(Problem) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .emptyKey }
        let client: GarminClient
        do {
            client = try makeClient(key)
            _ = try await client.getAccessToken(forceRefresh: true)
            try keychain.set(Data(key.utf8), for: Self.keyAccount)
        } catch {
            throw Problem(error)
        }
        state = .signedIn(client)
    }

    /// Explore the app with synthetic data; nothing is sent to Garmin or stored.
    func startDemo() {
        let client = try? GarminClient(
            apiKey: "demo", tokenCache: MemoryTokenCache(), transport: DemoTransport(),
            environment: ProcessEnvironment(variables: [:], homeDirectory: .temporaryDirectory))
        if let client {
            isDemo = true
            state = .signedIn(client)
        }
    }

    /// Forget the key, the cached token and everything saved from Garmin.
    func signOut() {
        if !isDemo {
            try? keychain.remove(Self.keyAccount)
            try? keychain.remove(KeychainTokenCache.account)
            snapshots?.removeAll()
            recordings?.removeAll()
        }
        isDemo = false
        state = .signedOut
    }

    /// A session for SwiftUI previews, separate from the app's Keychain items.
    static var preview: Session {
        Session(keychain: KeychainStore(service: "dev.camminady.gcpapi-sync.preview"))
    }
}
