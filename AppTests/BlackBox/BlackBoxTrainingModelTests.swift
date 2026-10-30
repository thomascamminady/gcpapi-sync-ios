import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

private typealias DataScript = BlackBoxScript<TrainingData>
private typealias HealthScript = BlackBoxScript<HealthHistory>
private typealias RecordingScript = BlackBoxScript<Data?>

private func describe(_ phase: TrainingModel.Phase) -> String {
    switch phase {
    case .loading: "loading"
    case .loaded: "loaded"
    case .failed: "failed"
    }
}

private func describe(_ phase: TrainingModel.RecoveryPhase) -> String {
    switch phase {
    case .loading: "loading"
    case .loaded: "loaded"
    case .failed: "failed"
    }
}

private func describe(_ phase: TrainingModel.TrackPhase?) -> String {
    switch phase {
    case nil: "none"
    case .loading: "loading"
    case .loaded: "loaded"
    case .unavailable: "unavailable"
    case .failed: "failed"
    }
}

private func shown(_ phase: TrainingModel.Phase) -> TrainingData? {
    if case .loaded(let data) = phase { data } else { nil }
}

/// A FIT recording of a ten-minute run, one record every five seconds.
private func recording() -> Data {
    let start = Date(timeIntervalSince1970: 1_793_300_000)
    let records = (0..<120).map { index in
        FITActivity.Record(
            time: start.addingTimeInterval(Double(index) * 5),
            latitude: 49.0 + Double(index) * 1e-4, longitude: 8.4, altitude: 120,
            heartRate: 140 + index % 10, cadence: 170, distance: Double(index) * 15,
            speed: 3, power: nil)
    }
    return FITWriter.encode(FITActivity(records: records))
}

@Suite("Training model")
struct BlackBoxTrainingModelTests {
    private let today = GarminDate.day("2026-10-30")
    private let first = TrainingData.sample(endingOn: .day("2026-10-30"))
    private let second = TrainingData.sample(endingOn: .day("2026-10-23"))
    private let health = HealthHistory.sample(endingOn: .day("2026-10-30"), days: 210)

    private func model(
        _ data: DataScript, health: HealthScript, recordings: RecordingScript? = nil,
        clock: BlackBoxClock = BlackBoxClock()
    ) -> TrainingModel {
        let today = today
        let recordings = recordings ?? RecordingScript([], otherwise: .value(nil))
        return TrainingModel(
            today: { today }, now: { clock.now },
            fetch: { date, analysis in
                try await data.play("\(date) \(analysis.fitnessDays) \(analysis.fatigueDays)")
            },
            fetchHealth: { date, days in try await health.play("\(date) \(days)") },
            fetchRecording: { id in try await recordings.play("\(id)") })
    }

    @Test("Loading fetches the training data, then the recovery response")
    func load() async {
        let data = DataScript([], otherwise: .value(first))
        let health = HealthScript([], otherwise: .value(health))
        let clock = BlackBoxClock()
        let model = model(data, health: health, clock: clock)
        #expect(describe(model.phase) == "loading")
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(model.lastUpdated == clock.now)
        #expect(model.refreshProblem == nil)
        #expect(await data.calls == ["\(today) 42.0 7.0"])
        let healthCalls = await health.calls
        #expect(healthCalls.count == 1)
        #expect(healthCalls.first?.hasPrefix("\(today) ") == true)
        guard case .loaded(let response) = model.recovery else {
            Issue.record("The recovery response is \(describe(model.recovery))")
            return
        }
        let expected = RecoveryResponse(
            history: self.health, loads: first.loadHistory, hardShare: model.analysis.hardShare,
            baselineDays: model.analysis.baselineDays)
        #expect(response.hardShare == model.analysis.hardShare)
        #expect(response.baselineDays == model.analysis.baselineDays)
        #expect(response.threshold == expected.threshold)
        #expect(response.hardDays == expected.hardDays)
        #expect(response.curves == expected.curves)
    }

    @Test("The analysis settings reach the fetch and the recovery response")
    func analysis() async {
        let data = DataScript([], otherwise: .value(first))
        let model = model(data, health: HealthScript([], otherwise: .value(health)))
        model.analysis.fitnessDays = 28
        model.analysis.fatigueDays = 5
        model.analysis.hardShare = 0.3
        model.analysis.baselineDays = 21
        await model.load()
        #expect(await data.calls == ["\(today) 28.0 5.0"])
        guard case .loaded(let response) = model.recovery else {
            Issue.record("The recovery response is \(describe(model.recovery))")
            return
        }
        #expect(response.hardShare == 0.3)
        #expect(response.baselineDays == 21)
    }

    @Test("A failed recovery response leaves the training data")
    func recoveryFailure() async {
        let model = model(
            DataScript([], otherwise: .value(first)),
            health: HealthScript([], otherwise: .failure(BlackBoxError(code: 1))))
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(describe(model.recovery) == "failed")
    }

    @Test("A failed first load fails in place")
    func firstFailure() async {
        let model = model(
            DataScript([.failure(BlackBoxError(code: 2))], otherwise: .value(first)),
            health: HealthScript([], otherwise: .value(health)))
        await model.load()
        #expect(describe(model.phase) == "failed")
        #expect(model.lastUpdated == nil)
        await model.load()
        #expect(shown(model.phase) == first)
    }

    @Test("A failed refresh keeps the older data and says so")
    func refreshFailure() async {
        let clock = BlackBoxClock()
        let model = model(
            DataScript(
                [.value(first), .failure(BlackBoxError(code: 3))], otherwise: .value(second)),
            health: HealthScript([], otherwise: .value(health)), clock: clock)
        await model.load()
        let loadedAt = clock.now
        clock.advance(600)
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(model.refreshProblem != nil)
        #expect(model.lastUpdated == loadedAt)
        await model.load()
        #expect(shown(model.phase) == second)
        #expect(model.refreshProblem == nil)
    }

    @Test("A cancelled refresh is no failure")
    func cancelledRefresh() async {
        let model = model(
            DataScript([.value(first), .cancellation], otherwise: .value(second)),
            health: HealthScript([], otherwise: .value(health)))
        await model.load()
        await model.load()
        #expect(shown(model.phase) == first)
        #expect(model.refreshProblem == nil)
    }

    @Test("A cancelled first load is no failure")
    func cancelledFirstLoad() async {
        let model = model(
            DataScript([.cancellation], otherwise: .value(first)),
            health: HealthScript([], otherwise: .value(health)))
        await model.load()
        #expect(describe(model.phase) != "failed")
    }

    @Test("Loading if needed: only when the data is older than the maximum age")
    func loadIfNeeded() async {
        let data = DataScript([], otherwise: .value(first))
        let clock = BlackBoxClock()
        let model = model(data, health: HealthScript([], otherwise: .value(health)), clock: clock)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        clock.advance(14 * 60)
        await model.loadIfNeeded()
        #expect(await data.count == 1)
        clock.advance(2 * 60)
        await model.loadIfNeeded()
        #expect(await data.count == 2)
        clock.advance(100)
        await model.loadIfNeeded(maxAge: 60)
        #expect(await data.count == 3)
    }
}

@Suite("Training model: recordings")
struct BlackBoxTrainingTrackTests {
    private func model(_ recordings: RecordingScript) -> TrainingModel {
        TrainingModel(
            today: { .day("2026-10-30") },
            fetch: { date, _ in TrainingData.sample(endingOn: date) },
            fetchHealth: { date, days in HealthHistory.sample(endingOn: date, days: days) },
            fetchRecording: { id in try await recordings.play("\(id)") })
    }

    private func workout(_ id: Int) throws -> Workout {
        try AnalyticsBlackBox.workout(id: id, on: .day("2026-10-28"), load: 80)
    }

    @Test("A FIT recording is analyzed")
    func loaded() async throws {
        let model = model(RecordingScript([], otherwise: .value(recording())))
        await model.loadTrack(for: try workout(11))
        guard case .loaded(let track)? = model.tracks[11] else {
            Issue.record("The track is \(describe(model.tracks[11]))")
            return
        }
        #expect(track.samples.count > 1)
        #expect(!track.route.isEmpty)
        #expect(track.duration > 0)
    }

    @Test(
        "No recording, or one that is not FIT, is unavailable", arguments: [nil, "not a FIT file"])
    func unavailable(content: String?) async throws {
        let model = model(RecordingScript([], otherwise: .value(content.map { Data($0.utf8) })))
        await model.loadTrack(for: try workout(12))
        #expect(describe(model.tracks[12]) == "unavailable")
    }

    @Test("A failed download fails, and a retry fetches again")
    func failure() async throws {
        let recordings = RecordingScript(
            [.failure(BlackBoxError(code: 7))], otherwise: .value(recording()))
        let model = model(recordings)
        let workout = try workout(13)
        await model.loadTrack(for: workout)
        #expect(describe(model.tracks[13]) == "failed")
        await model.loadTrack(for: workout)
        #expect(describe(model.tracks[13]) == "loaded")
        #expect(await recordings.calls == ["13", "13"])
    }

    @Test("A loaded recording is not downloaded again, until the tracks are reset")
    func cached() async throws {
        let recordings = RecordingScript([], otherwise: .value(recording()))
        let model = model(recordings)
        let workout = try workout(14)
        await model.loadTrack(for: workout)
        await model.loadTrack(for: workout)
        #expect(await recordings.count == 1)
        model.resetTracks()
        #expect(model.tracks.isEmpty)
        await model.loadTrack(for: workout)
        #expect(await recordings.count == 2)
        #expect(describe(model.tracks[14]) == "loaded")
    }

    @Test("Recordings are kept by activity")
    func byActivity() async throws {
        let recordings = RecordingScript(
            [.value(recording()), .value(nil)], otherwise: .value(nil))
        let model = model(recordings)
        await model.loadTrack(for: try workout(21))
        await model.loadTrack(for: try workout(22))
        #expect(describe(model.tracks[21]) == "loaded")
        #expect(describe(model.tracks[22]) == "unavailable")
        #expect(await recordings.calls == ["21", "22"])
    }
}
