import Foundation
import GCPAPISync
import Observation

/// The dashboard's week, the longer ranges of the detail screens, and the state of loading
/// them.
@Observable
final class HealthModel {
    enum Phase: Equatable {
        case loading
        case loaded(HealthHistory)
        case failed(Problem)
    }

    /// The number of days on the dashboard.
    nonisolated static let dashboardDays = 7

    private(set) var phase: Phase = .loading
    /// A failed refresh while older data is shown.
    private(set) var refreshProblem: Problem?
    private(set) var lastUpdated: Date?
    /// Histories fetched so far, by number of days.
    private(set) var histories: [Int: HealthHistory] = [:]
    /// Why a history could not be fetched, by number of days.
    private(set) var historyProblems: [Int: Problem] = [:]

    private let fetch: @Sendable (_ end: GarminDate, _ days: Int) async throws -> HealthHistory
    private let today: () -> GarminDate

    /// A model loading the `days` days ending on a date with `fetch`.
    init(
        today: @escaping () -> GarminDate = { GarminDate.today() },
        fetch: @escaping @Sendable (_ end: GarminDate, _ days: Int) async throws -> HealthHistory
    ) {
        self.today = today
        self.fetch = fetch
    }

    /// A model loading from Garmin through `client`.
    convenience init(client: GarminClient) {
        self.init { end, days in
            try await HealthLoader.load(from: client, endingOn: end, days: days)
        }
    }

    /// Load (or reload) the dashboard's week. Keeps showing older data if a refresh fails.
    func load() async {
        do {
            let week = try await fetch(today(), Self.dashboardDays)
            phase = .loaded(week)
            // Longer ranges are fetched again when they are next shown.
            histories = [Self.dashboardDays: week]
            historyProblems = [:]
            refreshProblem = nil
            lastUpdated = .now
        } catch {
            // Pull to refresh cancels its task when the gesture ends; that is no failure.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if case .loaded = phase {
                refreshProblem = Problem(error)
            } else {
                phase = .failed(Problem(error))
            }
        }
    }

    /// Fetch the last `days` days, unless they are already loaded.
    func loadHistory(days: Int) async {
        guard histories[days] == nil else { return }
        historyProblems[days] = nil
        do {
            histories[days] = try await fetch(today(), days)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            historyProblems[days] = Problem(error)
        }
    }
}
