import Foundation
import GCPAPISync
import Security
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// What went wrong, classified from what the client throws.
@Suite struct BlackBoxProblemTests {
    nonisolated private static let simple: [Problem] = [
        .emptyKey, .keyRejected, .offline, .timedOut, .rateLimited, .garminUnavailable,
        .keychain,
    ]

    nonisolated private static let all: [Problem] = simple + [.unexpected("blackbox detail")]

    /// The problem of fetching heart rate zones through `client`.
    private func problem(of client: GarminClient) async throws -> Problem {
        let error = await BlackBox.error { _ = try await client.getHeartRateZones() }
        return Problem(try #require(error))
    }

    /// A client whose key exchange answers `status`.
    private func exchanging(status: Int) throws -> GarminClient {
        let transport = StubTransport { request in
            request.path == tokenPath ? (status, "{}") : (200, "[]")
        }
        return try client(transport, apiKey: "blackbox-key")
    }

    // MARK: - Presentable

    @Test(arguments: all)
    func everyProblemIsPresentable(problem: Problem) {
        #expect(!problem.title.isEmpty)
        #expect(!problem.message.isEmpty)
        #expect(BlackBox.isSymbol(problem.symbol), "\(problem.symbol)")
        #expect(problem.title != problem.message)
    }

    @Test func problemsNeedingDifferentActionsSayDifferentThings() {
        let distinct: [Problem] = [.emptyKey, .keyRejected, .offline, .rateLimited, .keychain]
        #expect(Set(distinct.map(\.message)).count == distinct.count)
        #expect(Set(distinct.map(\.title)).count == distinct.count)
        #expect(Problem.keyRejected.title != Problem.garminUnavailable.title)
        #expect(Problem.offline.title != Problem.garminUnavailable.title)
    }

    @Test func unexpectedProblemsKeepTheirDetail() {
        #expect(Problem.unexpected("Disk 42 exploded").message.contains("Disk 42 exploded"))
        #expect(Problem.unexpected("a") != Problem.unexpected("b"))
        let detail = "a"
        #expect(Problem.unexpected(detail) == Problem.unexpected("a"))
    }

    // MARK: - Classification

    @Test(arguments: all)
    func aProblemIsItsOwnClassification(problem: Problem) {
        #expect(Problem(problem) == problem)
    }

    @Test(arguments: [401, 403])
    func aRejectedKeyExchangeMeansTheKeyWasRejected(status: Int) async throws {
        #expect(try await problem(of: exchanging(status: status)) == .keyRejected)
    }

    @Test func anExpiredTokenThatCannotBeRenewedMeansTheKeyWasRejected() async throws {
        #expect(try await problem(of: BlackBox.failing(status: 401)) == .keyRejected)
    }

    @Test func tooManyRequestsMeansRateLimited() async throws {
        #expect(try await problem(of: BlackBox.failing(status: 429)) == .rateLimited)
        #expect(try await problem(of: exchanging(status: 429)) == .rateLimited)
    }

    @Test(arguments: [500, 502, 503, 504, 599])
    func serverErrorsMeanGarminIsUnavailable(status: Int) async throws {
        #expect(try await problem(of: BlackBox.failing(status: status)) == .garminUnavailable)
        #expect(try await problem(of: exchanging(status: status)) == .garminUnavailable)
    }

    @Test(arguments: [400, 404, 405, 409, 418, 422])
    func otherStatusesAreNeitherTheKeyNorTheNetwork(status: Int) async throws {
        let problem = try await problem(of: BlackBox.failing(status: status))
        let wrong: [Problem] = [.emptyKey, .keyRejected, .offline, .timedOut, .keychain]
        #expect(!wrong.contains(problem), "\(problem)")
    }

    @Test func aTimeoutMeansTimedOut() async throws {
        #expect(try await problem(of: BlackBox.unreachable(timeout: true)) == .timedOut)
    }

    @Test func noConnectionMeansOffline() async throws {
        #expect(try await problem(of: BlackBox.unreachable(timeout: false)) == .offline)
    }

    @Test func aMalformedResponseIsNotTheUsersFault() async throws {
        let transport = StubTransport { request in
            request.path == tokenPath ? (200, "blackbox-token") : (200, "{not json")
        }
        let problem = try await problem(of: client(transport, apiKey: "blackbox-key"))
        let wrong: [Problem] = [.emptyKey, .keyRejected, .offline, .timedOut, .keychain]
        #expect(!wrong.contains(problem), "\(problem)")
    }

    @Test func anEmptyTokenIsNotTheUsersFault() async throws {
        let transport = StubTransport { request in
            request.path == tokenPath ? (200, "  \n") : (200, "[]")
        }
        let problem = try await problem(of: client(transport, apiKey: "blackbox-key"))
        let wrong: [Problem] = [.emptyKey, .offline, .timedOut, .keychain, .rateLimited]
        #expect(!wrong.contains(problem), "\(problem)")
    }

    @Test(arguments: [errSecInteractionNotAllowed, errSecDuplicateItem, errSecItemNotFound])
    func keychainErrorsMeanTheKeychain(status: OSStatus) {
        #expect(Problem(KeychainError(status: status)) == .keychain)
    }

    @Test func anyOtherErrorIsUnexpected() {
        let problem = Problem(BlackBoxStrangeError(code: 7))
        guard case .unexpected(let detail) = problem else {
            Issue.record("\(problem)")
            return
        }
        #expect(!detail.isEmpty)
    }

    @Test func anInvalidDateArgumentIsUnexpected() async throws {
        let api = try client(garmin(), apiKey: "good-key")
        let error = await BlackBox.error {
            _ = try await api.getDailySleepSummaries(start: "2026-13-45", end: "2026-10-01")
        }
        let problem = Problem(try #require(error))
        let wrong: [Problem] = [.keyRejected, .offline, .timedOut, .keychain, .rateLimited]
        #expect(!wrong.contains(problem), "\(problem)")
    }
}
