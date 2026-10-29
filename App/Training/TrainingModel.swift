import Foundation
import GCPAPISync
import Observation

/// The training screens' data and the state of loading it.
@Observable
final class TrainingModel {
    enum Phase: Equatable {
        case loading
        case loaded(TrainingData)
        case failed(Problem)
    }

    private(set) var phase: Phase = .loading
    /// A failed refresh while older data is shown.
    private(set) var refreshProblem: Problem?
    private(set) var lastUpdated: Date?

    private let fetch: @Sendable (_ end: GarminDate) async throws -> TrainingData
    private let today: () -> GarminDate
    private let now: () -> Date

    init(
        today: @escaping () -> GarminDate = { GarminDate.today() },
        now: @escaping () -> Date = { .now },
        fetch: @escaping @Sendable (_ end: GarminDate) async throws -> TrainingData
    ) {
        self.today = today
        self.now = now
        self.fetch = fetch
    }

    /// A model loading from Garmin through `client`.
    convenience init(client: GarminClient) {
        self.init { end in try await TrainingLoader.load(from: client, endingOn: end) }
    }

    /// Load unless the data is less than `maxAge` seconds old.
    func loadIfNeeded(maxAge: TimeInterval = 15 * 60) async {
        if let lastUpdated, now().timeIntervalSince(lastUpdated) < maxAge {
            return
        }
        await load()
    }

    /// Load (or reload). Keeps showing older data if a refresh fails.
    func load() async {
        do {
            phase = .loaded(try await fetch(today()))
            refreshProblem = nil
            lastUpdated = now()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if case .loaded = phase {
                refreshProblem = Problem(error)
            } else {
                phase = .failed(Problem(error))
            }
        }
    }
}
