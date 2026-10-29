import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

@Suite struct KeychainTests {
    @Test func storeRoundTrip() throws {
        let keychain = ScratchKeychain()
        let store = keychain.store
        #expect(try store.data(for: "item") == nil)
        try store.set(Data("one".utf8), for: "item")
        #expect(try store.data(for: "item") == Data("one".utf8))
        try store.set(Data("two".utf8), for: "item")
        #expect(try store.data(for: "item") == Data("two".utf8))
        try store.remove("item")
        #expect(try store.data(for: "item") == nil)
        try store.remove("item")
    }

    @Test func tokenCache() throws {
        let keychain = ScratchKeychain()
        let cache = KeychainTokenCache(store: keychain.store)
        let token = AccessToken(
            value: "secret", expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        #expect(cache.load("fingerprint") == nil)
        try cache.save(token, for: "fingerprint")
        #expect(cache.load("fingerprint") == token)
        #expect(cache.load("another key") == nil)
        try keychain.store.set(Data("garbage".utf8), for: KeychainTokenCache.account)
        #expect(cache.load("fingerprint") == nil)
        try cache.clear()
        #expect(try keychain.store.data(for: KeychainTokenCache.account) == nil)
    }
}

@Suite struct SessionTests {
    @Test func connectStoresAWorkingKey() async throws {
        let keychain = ScratchKeychain()
        let session = Session(keychain: keychain.store, transport: garmin())
        #expect(!session.isSignedIn)

        try await session.connect(apiKey: "  good-key\n")

        #expect(session.isSignedIn)
        #expect(!session.isDemo)
        #expect(try keychain.store.data(for: Session.keyAccount) == Data("good-key".utf8))
        #expect(try keychain.store.data(for: KeychainTokenCache.account) != nil)
        // A new launch restores the session from the Keychain.
        #expect(Session(keychain: keychain.store, transport: garmin()).isSignedIn)
    }

    @Test func rejectedKeysAreNotStored() async throws {
        let keychain = ScratchKeychain()
        let session = Session(keychain: keychain.store, transport: garmin())
        await #expect(throws: Problem.keyRejected) {
            try await session.connect(apiKey: "wrong-key")
        }
        #expect(!session.isSignedIn)
        #expect(try keychain.store.data(for: Session.keyAccount) == nil)
    }

    @Test func emptyKeysAreRejectedLocally() async {
        let transport = garmin()
        let session = Session(keychain: ScratchKeychain().store, transport: transport)
        await #expect(throws: Problem.emptyKey) {
            try await session.connect(apiKey: "  \n")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test func offlineConnectionsAreExplained() async {
        let transport = StubTransport { _ in (503, "") }
        let session = Session(keychain: ScratchKeychain().store, transport: transport)
        await #expect(throws: Problem.garminUnavailable) {
            try await session.connect(apiKey: "good-key")
        }
    }

    @Test func signOutForgetsEverything() async throws {
        let keychain = ScratchKeychain()
        let session = Session(keychain: keychain.store, transport: garmin())
        try await session.connect(apiKey: "good-key")

        session.signOut()

        #expect(!session.isSignedIn)
        #expect(try keychain.store.data(for: Session.keyAccount) == nil)
        #expect(try keychain.store.data(for: KeychainTokenCache.account) == nil)
    }

    @Test func demoDoesNotTouchTheKeychain() throws {
        let keychain = ScratchKeychain()
        try keychain.store.set(Data("kept".utf8), for: "other")
        let session = Session(keychain: keychain.store)
        session.startDemo()
        #expect(session.isSignedIn)
        #expect(session.isDemo)
        session.signOut()
        #expect(!session.isDemo)
        #expect(try keychain.store.data(for: "other") == Data("kept".utf8))
        try keychain.store.remove("other")
    }
}
