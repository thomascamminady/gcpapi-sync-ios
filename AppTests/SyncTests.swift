import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A directory of its own, deleted when the test is done.
private final class ScratchDirectory {
    let url = URL.temporaryDirectory.appending(path: "sync-tests-\(UUID().uuidString)")

    var snapshots: SnapshotStore { SnapshotStore(directory: url.appending(path: "Snapshots")) }
    var recordings: RecordingCache { RecordingCache(directory: url.appending(path: "Recordings")) }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite struct StorageTests {
    private let end = GarminDate.day("2026-10-29")

    @Test func snapshotsRoundTrip() throws {
        let scratch = ScratchDirectory()
        let store = scratch.snapshots
        #expect(store.load(HealthHistory.self, named: "week") == nil)
        let week = HealthHistory.sample(endingOn: end)
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        try store.save(week, as: "week", at: saved)
        let loaded = try #require(store.load(HealthHistory.self, named: "week"))
        #expect(loaded.value == week)
        #expect(loaded.saved == saved)
        let training = TrainingData.sample(endingOn: end)
        try store.save(training, as: "training")
        #expect(store.load(TrainingData.self, named: "training")?.value == training)
        // Snapshots can be fetched again, so they stay out of backups.
        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        store.removeAll()
        #expect(store.load(HealthHistory.self, named: "week") == nil)
    }

    @Test func aDamagedSnapshotIsIgnored() throws {
        let scratch = ScratchDirectory()
        try scratch.snapshots.save(HealthHistory.sample(endingOn: end), as: "week")
        try Data("not json".utf8).write(
            to: scratch.snapshots.directory.appending(path: "week.json"))
        #expect(scratch.snapshots.load(HealthHistory.self, named: "week") == nil)
        // A snapshot of another type does not decode as this one.
        try scratch.snapshots.save(TrainingData.sample(endingOn: end), as: "training")
        #expect(scratch.snapshots.load(HealthHistory.self, named: "training") == nil)
    }

    @Test func recordingsAreCached() {
        let scratch = ScratchDirectory()
        let cache = scratch.recordings
        #expect(cache.data(for: 7) == nil)
        cache.store(Data([1, 2, 3]), for: 7)
        #expect(cache.data(for: 7) == Data([1, 2, 3]))
        cache.removeAll()
        #expect(cache.data(for: 7) == nil)
    }

    @Test func recoveryResponsesRoundTrip() throws {
        let scratch = ScratchDirectory()
        let data = TrainingData.sample(endingOn: end)
        let response = RecoveryResponse(
            history: .sample(endingOn: end, days: data.loadHistory.count), loads: data.loadHistory)
        try scratch.snapshots.save(response, as: "recovery")
        #expect(scratch.snapshots.load(RecoveryResponse.self, named: "recovery")?.value == response)
    }
}

@Suite struct CachedModelTests {
    private let end = GarminDate.day("2026-10-29")

    @Test func healthOpensWithTheSavedWeekAndSavesNewOnes() async throws {
        let scratch = ScratchDirectory()
        let saved = HealthHistory.sample(endingOn: end.adding(days: -1))
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        try scratch.snapshots.save(saved, as: HealthModel.snapshot, at: then)
        let model = HealthModel(store: scratch.snapshots) { end, days in
            .sample(endingOn: end, days: days)
        }
        #expect(model.phase == .loaded(saved))
        #expect(model.lastUpdated == then)
        await model.load()
        let fresh = HealthHistory.sample(endingOn: .today())
        #expect(model.phase == .loaded(fresh))
        #expect(
            scratch.snapshots.load(HealthHistory.self, named: HealthModel.snapshot)?.value == fresh)
    }

    @Test func trainingOpensWithTheSavedDataAndSavesNewData() async throws {
        let scratch = ScratchDirectory()
        let saved = TrainingData.sample(endingOn: end.adding(days: -1))
        try scratch.snapshots.save(saved, as: TrainingModel.snapshot)
        let model = TrainingModel(
            today: { end }, store: scratch.snapshots, fetch: { end, _ in .sample(endingOn: end) },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) })
        #expect(model.phase == .loaded(saved))
        #expect(model.recovery == .loading)
        await model.load()
        #expect(
            scratch.snapshots.load(TrainingData.self, named: TrainingModel.snapshot)?.value
                == .sample(endingOn: end))
        let response = try #require(
            scratch.snapshots.load(RecoveryResponse.self, named: TrainingModel.recoverySnapshot))
        let reopened = TrainingModel(
            store: scratch.snapshots, fetch: { end, _ in .sample(endingOn: end) },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) })
        #expect(reopened.recovery == .loaded(response.value))
    }

    @Test func recordingsAreDownloadedOnce() async throws {
        let scratch = ScratchDirectory()
        let run = try #require(
            (0..<7).lazy.compactMap { SummarizedActivity.sampleRun(on: end.adding(days: -$0)) }
                .first)
        let workout = try #require(Workout(run))
        let archive = StoredZip.archive(
            name: "\(run.activityId)_ACTIVITY.fit", content: FITWriter.encode(.sample(of: run)))
        let transport = ZipTransport(archive: archive)
        let first = TrainingModel(client: try client(transport), recordings: scratch.recordings)
        await first.loadTrack(for: workout)
        guard case .loaded = first.tracks[workout.id] else {
            Issue.record("the recording did not load")
            return
        }
        #expect(scratch.recordings.data(for: workout.id) != nil)
        let second = TrainingModel(client: try client(transport), recordings: scratch.recordings)
        await second.loadTrack(for: workout)
        guard case .loaded = second.tracks[workout.id] else {
            Issue.record("the cached recording did not load")
            return
        }
        #expect(await transport.downloads == 1)
    }
}

/// Serves `archive` for every activity download and counts the downloads.
private final class ZipTransport: HTTPTransport {
    let archive: Data
    private let counter = Counter()

    init(archive: Data) {
        self.archive = archive
    }

    var downloads: Int {
        get async { await counter.count }
    }

    func send(_ request: HTTPRequest) async -> HTTPResponse {
        if request.path == tokenPath {
            return HTTPResponse(statusCode: 200, body: Data("token".utf8), request: request)
        }
        await counter.increment()
        return HTTPResponse(statusCode: 200, body: archive, request: request)
    }

    private actor Counter {
        var count = 0

        func increment() {
            count += 1
        }
    }
}

@Suite struct SessionStorageTests {
    @Test func theStoredKeyMakesAClient() throws {
        let keychain = ScratchKeychain()
        #expect(Session.storedClient(keychain: keychain.store) == nil)
        try keychain.store.set(Data("good-key".utf8), for: Session.keyAccount)
        #expect(Session.storedClient(keychain: keychain.store) != nil)
    }

    @Test func signingOutDeletesWhatWasSaved() async throws {
        let scratch = ScratchDirectory()
        let keychain = ScratchKeychain()
        let session = Session(
            keychain: keychain.store, transport: garmin(), snapshots: scratch.snapshots,
            recordings: scratch.recordings)
        try await session.connect(apiKey: "good-key")
        try scratch.snapshots.save(HealthHistory(days: []), as: "week")
        scratch.recordings.store(Data([1]), for: 1)
        session.signOut()
        #expect(scratch.snapshots.load(HealthHistory.self, named: "week") == nil)
        #expect(scratch.recordings.data(for: 1) == nil)
    }

    @Test func theDemoKeepsWhatWasSaved() throws {
        let scratch = ScratchDirectory()
        let session = Session(
            keychain: ScratchKeychain().store, snapshots: scratch.snapshots,
            recordings: scratch.recordings)
        try scratch.snapshots.save(HealthHistory(days: []), as: "week")
        session.startDemo()
        session.signOut()
        #expect(scratch.snapshots.load(HealthHistory.self, named: "week") != nil)
    }
}

@Suite struct BackgroundRefreshTests {
    private let end = GarminDate.day("2026-10-29")

    @Test func refreshesAndSavesTheWeekAndTheTraining() async throws {
        let scratch = ScratchDirectory()
        await BackgroundRefresh.run(
            settings: Settings(), client: try client(DemoTransport()), store: scratch.snapshots,
            today: end)
        #expect(
            scratch.snapshots.load(HealthHistory.self, named: HealthModel.snapshot)?.value
                == .sample(endingOn: end))
        #expect(
            scratch.snapshots.load(TrainingData.self, named: TrainingModel.snapshot)?.value
                == .sample(endingOn: end))
    }

    @Test func doesNothingWhenTurnedOffOrSignedOut() async throws {
        let scratch = ScratchDirectory()
        var off = Settings()
        off.refreshesInBackground = false
        await BackgroundRefresh.run(
            settings: off, client: try client(DemoTransport()), store: scratch.snapshots,
            today: end)
        await BackgroundRefresh.run(
            settings: Settings(), client: nil, store: scratch.snapshots, today: end)
        #expect(scratch.snapshots.load(HealthHistory.self, named: HealthModel.snapshot) == nil)
        #expect(Settings().refreshesInBackground)
    }
}
