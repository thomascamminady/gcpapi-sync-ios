import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Hands out queued results, one per load.
private actor Results {
    var queue: [Result<HealthWeek, Problem>]

    init(_ queue: [Result<HealthWeek, Problem>]) {
        self.queue = queue
    }

    func next() throws -> HealthWeek {
        try queue.removeFirst().get()
    }
}

@Suite struct WeekModelTests {
    private let end = GarminDate.day("2026-10-28")

    @Test func loadsTheWeekEndingToday() async {
        let model = WeekModel(
            today: { .day("2026-10-28") }, fetch: { day in .sample(endingOn: day) })
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .loaded(.sample(endingOn: end)))
        #expect(model.lastUpdated != nil)
        #expect(model.refreshProblem == nil)
    }

    @Test func aFirstFailureIsShownInPlace() async {
        let model = WeekModel { _ in throw Problem.offline }
        await model.load()
        #expect(model.phase == .failed(.offline))
    }

    @Test func aFailedRefreshKeepsTheData() async {
        let results = Results([
            .success(.sample(endingOn: end)), .failure(.rateLimited),
            .success(.sample(endingOn: end)),
        ])
        let model = WeekModel { _ in try await results.next() }
        await model.load()
        await model.load()
        #expect(model.phase == .loaded(.sample(endingOn: end)))
        #expect(model.refreshProblem == .rateLimited)
        await model.load()
        #expect(model.refreshProblem == nil)
    }

    @Test func cancellationIsNoFailure() async {
        let model = WeekModel { _ in throw CancellationError() }
        await model.load()
        #expect(model.phase == .loading)
    }

    @Test func garminErrorsBecomeProblems() async throws {
        let rejected = StubTransport { request in
            request.path == tokenPath ? (200, "token") : (401, "")
        }
        let model = WeekModel(client: try client(rejected))
        await model.load()
        #expect(model.phase == .failed(.keyRejected))
    }
}

@Suite struct ProblemTests {
    @Test(arguments: [
        Problem.emptyKey, .keyRejected, .offline, .timedOut, .rateLimited, .garminUnavailable,
        .keychain,
        .unexpected("detail"),
    ])
    func everyProblemIsExplained(problem: Problem) {
        #expect(!problem.title.isEmpty)
        #expect(!problem.message.isEmpty)
        #expect(!problem.symbol.isEmpty)
        #expect(Problem(problem) == problem)
    }

    @Test func classification() async {
        func failure(
            _ respond: @escaping @Sendable (HTTPRequest) -> (status: Int, body: String)
        ) async -> Problem? {
            do {
                _ = try await client(StubTransport(respond)).getAccessToken()
                return nil
            } catch {
                return Problem(error)
            }
        }
        #expect(await failure { _ in (429, "") } == .rateLimited)
        #expect(await failure { _ in (500, "") } == .garminUnavailable)
        #expect(
            await failure { _ in (418, "") } == .unexpected("POST \(tokenPath) returned HTTP 418"))
        #expect(Problem(KeychainError(status: -25_300)) == .keychain)
        #expect(Problem(CocoaError(.fileNoSuchFile)) != .keychain)
        #expect(Problem(TransportProblem()) == .unexpected("transport"))
    }

    private struct TransportProblem: LocalizedError {
        var errorDescription: String? { "transport" }
    }
}

@Suite struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(seconds: nil) == "–")
        #expect(
            Format.duration(seconds: 0)
                == Duration.seconds(0).formatted(
                    .units(allowed: [.hours, .minutes], width: .narrow)))
        #expect(Format.number(nil) == "–")
        #expect(Format.number(1234) == 1234.formatted())
    }

    @Test(arguments: ["BALANCED", "UNBALANCED", "LOW", "POOR"])
    func hrvStatuses(status: String) {
        #expect(Format.hrvStatus(status) != nil)
    }

    @Test func unknownHRVStatus() {
        #expect(Format.hrvStatus("NONE") == nil)
        #expect(Format.hrvStatus(nil) == nil)
    }

    @Test(
        arguments: [(nil, "–"), (10, "Resting"), (40, "Low"), (60, "Medium"), (90, "High")]
            as [(Int?, String)])
    func stressBands(level: Int?, label: String) {
        #expect(Format.stressLabel(level) == String(localized: String.LocalizationValue(label)))
        if let level {
            _ = Format.stressColor(level)
        }
    }
}
