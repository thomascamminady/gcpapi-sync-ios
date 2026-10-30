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

    /// An activity's recording, as far as it is loaded.
    enum TrackPhase: Equatable {
        case loading
        case loaded(ActivityTrack)
        /// No recording to show: manual activities, or files that are not FIT.
        case unavailable
        case failed(Problem)
    }

    private(set) var phase: Phase = .loading
    /// Recordings by activity id.
    private(set) var tracks: [Int: TrackPhase] = [:]
    /// The recovery response, loaded after the training data.
    private(set) var recovery: RecoveryPhase = .loading
    /// A failed refresh while older data is shown.
    private(set) var refreshProblem: Problem?
    private(set) var lastUpdated: Date?

    /// The parameters of the analyses; changing them takes a reload.
    var analysis = AnalysisSettings()

    private let fetch:
        @Sendable (_ end: GarminDate, _ analysis: AnalysisSettings) async throws -> TrainingData
    private let fetchHealth:
        @Sendable (_ end: GarminDate, _ days: Int) async throws -> HealthHistory
    private let fetchRecording: @Sendable (_ id: Int) async throws -> Data?
    private let today: () -> GarminDate
    private let now: () -> Date

    init(
        today: @escaping () -> GarminDate = { GarminDate.today() },
        now: @escaping () -> Date = { .now },
        fetch:
            @escaping @Sendable (_ end: GarminDate, _ analysis: AnalysisSettings) async throws
            -> TrainingData,
        fetchHealth:
            @escaping @Sendable (_ end: GarminDate, _ days: Int) async throws
            -> HealthHistory,
        fetchRecording: @escaping @Sendable (_ id: Int) async throws -> Data? = { _ in nil }
    ) {
        self.today = today
        self.now = now
        self.fetch = fetch
        self.fetchHealth = fetchHealth
        self.fetchRecording = fetchRecording
    }

    /// A model loading from Garmin through `client`.
    convenience init(client: GarminClient) {
        self.init(
            fetch: { end, analysis in
                try await TrainingLoader.load(from: client, endingOn: end, analysis: analysis)
            },
            fetchHealth: { end, days in
                try await HealthLoader.load(
                    from: client, endingOn: end, days: days, estimatingVO2max: false)
            },
            fetchRecording: { id in
                let file = try await client.downloadActivity(id)
                return file.fileExtension == "fit" ? file.content : nil
            })
    }

    /// Forget the analyzed recordings, as after changing units.
    func resetTracks() {
        tracks = [:]
    }

    /// Download and analyze `workout`'s recording, unless it is loaded already.
    func loadTrack(for workout: Workout) async {
        switch tracks[workout.id] {
        case .loaded, .unavailable, .loading: return
        case .failed, nil: break
        }
        tracks[workout.id] = .loading
        do {
            guard let data = try await fetchRecording(workout.id) else {
                tracks[workout.id] = .unavailable
                return
            }
            tracks[workout.id] = .loaded(
                try await TrackBuilder.track(
                    from: data, sport: workout.sport,
                    splitLength: Format.usesMiles ? 1609.344 : 1000))
        } catch is FITError {
            tracks[workout.id] = .unavailable
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else {
                tracks[workout.id] = nil
                return
            }
            tracks[workout.id] = .failed(Problem(error))
        }
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
            data = try await fetch(today(), analysis)
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
            recovery = .loaded(
                RecoveryResponse(
                    history: history, loads: data.loadHistory, hardShare: analysis.hardShare,
                    baselineDays: analysis.baselineDays))
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if case .loaded = recovery {
                return
            }
            recovery = .failed(Problem(error))
        }
    }
}
