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

    /// A session that restores a previously stored key.
    ///
    /// - Parameters:
    ///   - keychain: Where the key and the access token are kept.
    ///   - transport: How requests are sent; `nil` for the network.
    init(keychain: KeychainStore = .standard, transport: (any HTTPTransport)? = nil) {
        self.keychain = keychain
        self.transport = transport
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
        try GarminClient(
            apiKey: apiKey,
            tokenCache: KeychainTokenCache(store: keychain),
            transport: transport,
            // Configuration comes from this app, never from the process environment.
            environment: ProcessEnvironment(variables: [:], homeDirectory: .temporaryDirectory)
        )
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

    /// Forget the key and the cached token.
    func signOut() {
        if !isDemo {
            try? keychain.remove(Self.keyAccount)
            try? keychain.remove(KeychainTokenCache.account)
        }
        isDemo = false
        state = .signedOut
    }

    /// A session for SwiftUI previews, separate from the app's Keychain items.
    static var preview: Session {
        Session(keychain: KeychainStore(service: "dev.camminady.gcpapi-sync.preview"))
    }
}
