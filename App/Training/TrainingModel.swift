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

    enum RecoveryPhase: Equatable {
        case loading
        case loaded(RecoveryResponse)
        case failed(Problem)
    }

    private(set) var phase: Phase = .loading
    /// The recovery response, loaded after the training data.
    private(set) var recovery: RecoveryPhase = .loading
    /// A failed refresh while older data is shown.
    private(set) var refreshProblem: Problem?
    private(set) var lastUpdated: Date?

    private let fetch: @Sendable (_ end: GarminDate) async throws -> TrainingData
    private let fetchHealth:
        @Sendable (_ end: GarminDate, _ days: Int) async throws -> HealthHistory
    private let today: () -> GarminDate
    private let now: () -> Date

    init(
        today: @escaping () -> GarminDate = { GarminDate.today() },
        now: @escaping () -> Date = { .now },
        fetch: @escaping @Sendable (_ end: GarminDate) async throws -> TrainingData,
        fetchHealth:
            @escaping @Sendable (_ end: GarminDate, _ days: Int) async throws
            -> HealthHistory
    ) {
        self.today = today
        self.now = now
        self.fetch = fetch
        self.fetchHealth = fetchHealth
    }

    /// A model loading from Garmin through `client`.
    convenience init(client: GarminClient) {
        self.init(
            fetch: { end in try await TrainingLoader.load(from: client, endingOn: end) },
            fetchHealth: { end, days in
                try await HealthLoader.load(
                    from: client, endingOn: end, days: days, estimatingVO2max: false)
            })
    }

    /// Load unless the data is less than `maxAge` seconds old.
    func loadIfNeeded(maxAge: TimeInterval = 15 * 60) async {
        if let lastUpdated, now().timeIntervalSince(lastUpdated) < maxAge {
            return
        }
        await load()
    }

    /// Load (or reload), then the recovery response. Keeps showing older data if a refresh
    /// fails.
    func load() async {
        let data: TrainingData
        do {
            data = try await fetch(today())
            phase = .loaded(data)
            refreshProblem = nil
            lastUpdated = now()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if case .loaded = phase {
                refreshProblem = Problem(error)
            } else {
                phase = .failed(Problem(error))
            }
            return
        }
        await loadRecovery(data)
    }

    /// The recovery response over the days of `data`'s load history.
    private func loadRecovery(_ data: TrainingData) async {
        guard let end = data.loadHistory.last?.date else { return }
        do {
            let history = try await fetchHealth(end, data.loadHistory.count)
            recovery = .loaded(RecoveryResponse(history: history, loads: data.loadHistory))
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if case .loaded = recovery {
                return
            }
            recovery = .failed(Problem(error))
        }
    }
}
