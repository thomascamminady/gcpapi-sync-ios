import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Connecting, restoring, the demo and signing out.
@Suite struct BlackBoxSessionTests {
    /// The stored key, as text.
    private func storedKey(_ scratch: ScratchKeychain) throws -> String? {
        try scratch.store.data(for: Session.keyAccount).map { String(decoding: $0, as: UTF8.self) }
    }

    /// The session's client, if it is signed in.
    private func signedInClient(of session: Session) -> GarminClient? {
        guard case .signedIn(let client) = session.state else { return nil }
        return client
    }

    /// A Garmin that accepts every key in `keys`.
    private func accepting(_ keys: Set<String>) -> StubTransport {
        StubTransport { request in
            guard request.path == tokenPath else { return (404, "{}") }
            let key = request.header("Authorization").map { String($0.dropFirst(7)) } ?? ""
            return keys.contains(key) ? (200, "blackbox-token-\(key)") : (401, "{}")
        }
    }

    // MARK: - Starting

    @Test func withoutAStoredKeyTheSessionIsSignedOut() {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        #expect(!session.isSignedIn)
        #expect(!session.isDemo)
        #expect(signedInClient(of: session) == nil)
        #expect(Session.keyAccount != KeychainTokenCache.account)
    }

    @Test func aStoredKeyIsRestored() throws {
        let scratch = ScratchKeychain()
        try scratch.store.set(Data("good-key".utf8), for: Session.keyAccount)
        let session = Session(keychain: scratch.store, transport: garmin())
        #expect(session.isSignedIn)
        #expect(!session.isDemo)
        #expect(signedInClient(of: session) != nil)
    }

    // MARK: - Connecting

    @Test func anAcceptedKeySignsInAndIsRemembered() async throws {
        let scratch = ScratchKeychain()
        let transport = garmin()
        let session = Session(keychain: scratch.store, transport: transport)
        try await session.connect(apiKey: "good-key")
        #expect(session.isSignedIn)
        #expect(!session.isDemo)
        #expect(try storedKey(scratch) == "good-key")
        let requests = await transport.requests
        #expect(requests.contains { $0.path == tokenPath })
        #expect(requests.first?.header("Authorization") == "ApiKey good-key")
    }

    @Test func theTokenIsKeptForTheNextLaunch() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        try await session.connect(apiKey: "good-key")
        #expect(try scratch.store.data(for: KeychainTokenCache.account) != nil)

        let relaunch = garmin()
        let restored = Session(keychain: scratch.store, transport: relaunch)
        let client = try #require(signedInClient(of: restored))
        _ = try await client.getAccessToken()
        #expect(await relaunch.requests.isEmpty)
    }

    @Test func aRejectedKeyIsNotRemembered() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        await #expect(throws: Problem.keyRejected) {
            try await session.connect(apiKey: "wrong-key")
        }
        #expect(!session.isSignedIn)
        #expect(try scratch.store.data(for: Session.keyAccount) == nil)
        #expect(!Session(keychain: scratch.store, transport: garmin()).isSignedIn)
    }

    @Test func aRejectedKeyKeepsThePreviousOne() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        try await session.connect(apiKey: "good-key")
        await #expect(throws: Problem.keyRejected) {
            try await session.connect(apiKey: "wrong-key")
        }
        #expect(session.isSignedIn)
        #expect(try storedKey(scratch) == "good-key")
    }

    @Test func aNewKeyReplacesTheOld() async throws {
        let scratch = ScratchKeychain()
        let transport = accepting(["first-key", "second-key"])
        let session = Session(keychain: scratch.store, transport: transport)
        try await session.connect(apiKey: "first-key")
        try await session.connect(apiKey: "second-key")
        #expect(session.isSignedIn)
        #expect(try storedKey(scratch) == "second-key")
    }

    @Test(arguments: ["", " ", "\n", " \t\n "])
    func anEmptyKeyIsNotSent(key: String) async throws {
        let scratch = ScratchKeychain()
        let transport = garmin()
        let session = Session(keychain: scratch.store, transport: transport)
        await #expect(throws: Problem.emptyKey) { try await session.connect(apiKey: key) }
        #expect(!session.isSignedIn)
        #expect(await transport.requests.isEmpty)
        #expect(try scratch.store.data(for: Session.keyAccount) == nil)
    }

    @Test func surroundingWhitespaceOfAPastedKeyIsIgnored() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        try await session.connect(apiKey: "  good-key\n")
        #expect(session.isSignedIn)
        #expect(
            try storedKey(scratch)?.trimmingCharacters(in: .whitespacesAndNewlines)
                == "good-key")
    }

    @Test func connectingWithoutANetworkIsOffline() async throws {
        let scratch = ScratchKeychain()
        let transport = ThrowingTransport(error: TransportError("blackbox: offline"))
        let session = Session(keychain: scratch.store, transport: transport)
        await #expect(throws: Problem.offline) { try await session.connect(apiKey: "good-key") }
        #expect(!session.isSignedIn)
        #expect(try scratch.store.data(for: Session.keyAccount) == nil)
    }

    @Test func connectingCanTimeOut() async throws {
        let scratch = ScratchKeychain()
        let transport = ThrowingTransport(error: TransportError("blackbox", isTimeout: true))
        let session = Session(keychain: scratch.store, transport: transport)
        await #expect(throws: Problem.timedOut) { try await session.connect(apiKey: "good-key") }
        #expect(!session.isSignedIn)
    }

    @Test(arguments: [(429, Problem.rateLimited), (503, .garminUnavailable)])
    func connectingWhileGarminStrugglesSaysSo(status: Int, expected: Problem) async throws {
        let scratch = ScratchKeychain()
        let transport = StubTransport { _ in (status, "{}") }
        let session = Session(keychain: scratch.store, transport: transport)
        await #expect(throws: expected) { try await session.connect(apiKey: "good-key") }
        #expect(!session.isSignedIn)
        #expect(try scratch.store.data(for: Session.keyAccount) == nil)
    }

    // MARK: - Demo

    @Test func theDemoSendsAndStoresNothing() async throws {
        let scratch = ScratchKeychain()
        let transport = garmin()
        let session = Session(keychain: scratch.store, transport: transport)
        session.startDemo()
        #expect(session.isDemo)
        #expect(session.isSignedIn)
        let client = try #require(signedInClient(of: session))
        let zones = try await client.getHeartRateZones()
        #expect(!zones.isEmpty)
        #expect(await transport.requests.isEmpty)
        #expect(try scratch.store.data(for: Session.keyAccount) == nil)
        #expect(try scratch.store.data(for: KeychainTokenCache.account) == nil)
        #expect(!Session(keychain: scratch.store, transport: garmin()).isSignedIn)
    }

    @Test func connectingFromTheDemoRemembersTheKey() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        session.startDemo()
        try await session.connect(apiKey: "good-key")
        #expect(session.isSignedIn)
        #expect(try storedKey(scratch) == "good-key")
    }

    @Test func signingOutEndsTheDemo() {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        session.startDemo()
        session.signOut()
        #expect(!session.isDemo)
        #expect(!session.isSignedIn)
    }

    // MARK: - Signing out

    @Test func signingOutForgetsTheKeyAndTheToken() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        try await session.connect(apiKey: "good-key")
        session.signOut()
        #expect(!session.isSignedIn)
        #expect(signedInClient(of: session) == nil)
        #expect(try scratch.store.data(for: Session.keyAccount) == nil)
        #expect(try scratch.store.data(for: KeychainTokenCache.account) == nil)
        #expect(!Session(keychain: scratch.store, transport: garmin()).isSignedIn)
    }

    @Test func signingOutTwiceIsHarmless() {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        session.signOut()
        session.signOut()
        #expect(!session.isSignedIn)
        #expect(!session.isDemo)
    }

    @Test func signingInAgainAfterSigningOut() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        try await session.connect(apiKey: "good-key")
        session.signOut()
        try await session.connect(apiKey: "good-key")
        #expect(session.isSignedIn)
        #expect(try storedKey(scratch) == "good-key")
    }
}
