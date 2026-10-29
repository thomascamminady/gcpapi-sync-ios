import Foundation
import GCPAPISync
import Observation

/// The last week of health data and the state of loading it.
@Observable
final class WeekModel {
    enum Phase: Equatable {
        case loading
        case loaded(HealthWeek)
        case failed(Problem)
    }

    private(set) var phase: Phase = .loading
    /// A failed refresh while older data is shown.
    private(set) var refreshProblem: Problem?
    private(set) var lastUpdated: Date?

    private let fetch: @Sendable (GarminDate) async throws -> HealthWeek
    private let today: () -> GarminDate

    /// A model loading from `fetch`, for the week ending on `today()`.
    init(
        today: @escaping () -> GarminDate = { GarminDate.today() },
        fetch: @escaping @Sendable (GarminDate) async throws -> HealthWeek
    ) {
        self.today = today
        self.fetch = fetch
    }

    /// A model loading from Garmin through `client`.
    convenience init(client: GarminClient) {
        self.init { day in try await HealthWeekLoader.load(from: client, endingOn: day) }
    }

    /// Load (or reload) the week. Keeps showing older data if a refresh fails.
    func load() async {
        do {
            let week = try await fetch(today())
            phase = .loaded(week)
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
}
