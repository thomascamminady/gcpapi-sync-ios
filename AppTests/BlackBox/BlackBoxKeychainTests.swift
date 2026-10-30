import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Generic passwords in a throwaway Keychain service.
@Suite struct BlackBoxKeychainStoreTests {
    @Test func theAppsStoreHasItsOwnService() {
        #expect(!KeychainStore.standard.service.isEmpty)
        #expect(ScratchKeychain().store.service != KeychainStore.standard.service)
    }

    @Test func aMissingItemIsNil() throws {
        let scratch = ScratchKeychain()
        #expect(try scratch.store.data(for: "blackbox-missing") == nil)
    }

    @Test func storedDataIsReadBack() throws {
        let scratch = ScratchKeychain()
        let data = Data("secret value".utf8)
        try scratch.store.set(data, for: "blackbox-account")
        #expect(try scratch.store.data(for: "blackbox-account") == data)
    }

    @Test func storingAgainReplaces() throws {
        let scratch = ScratchKeychain()
        try scratch.store.set(Data("first".utf8), for: "blackbox-account")
        try scratch.store.set(Data("second, and longer".utf8), for: "blackbox-account")
        try scratch.store.set(Data("third".utf8), for: "blackbox-account")
        #expect(try scratch.store.data(for: "blackbox-account") == Data("third".utf8))
    }

    @Test func removingDeletes() throws {
        let scratch = ScratchKeychain()
        try scratch.store.set(Data("value".utf8), for: "blackbox-account")
        try scratch.store.remove("blackbox-account")
        #expect(try scratch.store.data(for: "blackbox-account") == nil)
        // Storing after removing works again.
        try scratch.store.set(Data("again".utf8), for: "blackbox-account")
        #expect(try scratch.store.data(for: "blackbox-account") == Data("again".utf8))
    }

    @Test func removingWhatIsNotThereIsFine() throws {
        let scratch = ScratchKeychain()
        try scratch.store.remove("blackbox-never-stored")
        try scratch.store.remove("blackbox-never-stored")
        #expect(try scratch.store.data(for: "blackbox-never-stored") == nil)
    }

    @Test func accountsAreIndependent() throws {
        let scratch = ScratchKeychain()
        try scratch.store.set(Data("one".utf8), for: "blackbox-one")
        try scratch.store.set(Data("two".utf8), for: "blackbox-two")
        try scratch.store.remove("blackbox-one")
        #expect(try scratch.store.data(for: "blackbox-one") == nil)
        #expect(try scratch.store.data(for: "blackbox-two") == Data("two".utf8))
    }

    @Test func servicesAreIndependent() throws {
        let first = ScratchKeychain()
        let second = ScratchKeychain()
        try first.store.set(Data("first".utf8), for: "blackbox-shared")
        #expect(try second.store.data(for: "blackbox-shared") == nil)
        try second.store.set(Data("second".utf8), for: "blackbox-shared")
        #expect(try first.store.data(for: "blackbox-shared") == Data("first".utf8))
        try first.store.remove("blackbox-shared")
        #expect(try second.store.data(for: "blackbox-shared") == Data("second".utf8))
    }

    @Test func anyBytesAndAnyAccountName() throws {
        let scratch = ScratchKeychain()
        let bytes = Data((0...255).map(UInt8.init) + Array(repeating: 0, count: 70_000))
        let account = "Konto \u{E4}\u{F6}\u{FC} \u{1F511} / with spaces"
        try scratch.store.set(bytes, for: account)
        #expect(try scratch.store.data(for: account) == bytes)
        #expect(try scratch.store.data(for: "Konto") == nil)
    }
}

/// The access token in the Keychain.
@Suite struct BlackBoxKeychainTokenCacheTests {
    private let token = AccessToken(
        value: "header.payload.signature", expiresAt: Date(timeIntervalSince1970: 1_893_456_000)
    )

    @Test func nothingIsCachedAtFirst() {
        let scratch = ScratchKeychain()
        let cache = KeychainTokenCache(store: scratch.store)
        #expect(cache.load("blackbox-fingerprint") == nil)
        #expect(cache.store.service == scratch.store.service)
        #expect(!KeychainTokenCache.account.isEmpty)
    }

    @Test func aSavedTokenIsLoadedForItsKey() throws {
        let scratch = ScratchKeychain()
        let cache = KeychainTokenCache(store: scratch.store)
        try cache.save(token, for: "blackbox-fingerprint")
        #expect(cache.load("blackbox-fingerprint") == token)
        #expect(KeychainTokenCache(store: scratch.store).load("blackbox-fingerprint") == token)
        #expect(try scratch.store.data(for: KeychainTokenCache.account) != nil)
    }

    @Test func aTokenIsOnlyLoadedForTheKeyItWasIssuedFor() throws {
        let scratch = ScratchKeychain()
        let cache = KeychainTokenCache(store: scratch.store)
        try cache.save(token, for: "blackbox-fingerprint")
        #expect(cache.load("another-fingerprint") == nil)
        #expect(cache.load("") == nil)
    }

    @Test func aNewTokenReplacesTheOld() throws {
        let scratch = ScratchKeychain()
        let cache = KeychainTokenCache(store: scratch.store)
        let newer = AccessToken(
            value: "newer", expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        try cache.save(token, for: "first")
        try cache.save(newer, for: "second")
        #expect(cache.load("second") == newer)
        #expect(cache.load("first") == nil)
    }

    @Test func clearingForgetsTheToken() throws {
        let scratch = ScratchKeychain()
        let cache = KeychainTokenCache(store: scratch.store)
        try cache.clear()
        try cache.save(token, for: "blackbox-fingerprint")
        try cache.clear()
        #expect(cache.load("blackbox-fingerprint") == nil)
        #expect(try scratch.store.data(for: KeychainTokenCache.account) == nil)
        try cache.clear()
    }

    @Test(arguments: ["", "garbage", "{}", #"{"value": 1}"#, "[1, 2]"])
    func anUnreadableTokenIsNotLoaded(stored: String) throws {
        let scratch = ScratchKeychain()
        try scratch.store.set(Data(stored.utf8), for: KeychainTokenCache.account)
        #expect(KeychainTokenCache(store: scratch.store).load("blackbox-fingerprint") == nil)
    }

    @Test func otherItemsAreLeftAlone() throws {
        let scratch = ScratchKeychain()
        try scratch.store.set(Data("key".utf8), for: "blackbox-other")
        let cache = KeychainTokenCache(store: scratch.store)
        try cache.save(token, for: "blackbox-fingerprint")
        try cache.clear()
        #expect(try scratch.store.data(for: "blackbox-other") == Data("key".utf8))
    }

    @Test func theClientReusesTheCachedTokenAcrossLaunches() async throws {
        let scratch = ScratchKeychain()
        let first = garmin()
        let firstClient = try GarminClient(
            apiKey: "good-key", tokenCache: KeychainTokenCache(store: scratch.store),
            retry: RetryConfig(maxRetries: 0), transport: first
        )
        let issued = try await firstClient.getAccessToken()
        let second = garmin()
        let secondClient = try GarminClient(
            apiKey: "good-key", tokenCache: KeychainTokenCache(store: scratch.store),
            retry: RetryConfig(maxRetries: 0), transport: second
        )
        let reused = try await secondClient.getAccessToken()
        #expect(reused.value == issued.value)
        #expect(abs(reused.expiresAt.timeIntervalSince(issued.expiresAt)) < 1)
        #expect(await first.requests.count == 1)
        #expect(await second.requests.isEmpty)
    }
}
