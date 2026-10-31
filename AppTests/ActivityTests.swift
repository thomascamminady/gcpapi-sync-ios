import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

nonisolated private let start = FITActivity.epoch.addingTimeInterval(1_100_000_000)

/// Records every `step` seconds at `speed`, with heart rate `heartRate(second)`.
nonisolated private func records(
    seconds: Double, step: Double = 1, speed: Double = 4, heartRate: (Double) -> Int = { _ in 150 }
) -> [FITActivity.Record] {
    stride(from: 0, through: seconds, by: step).map { second in
        FITActivity.Record(
            time: start.addingTimeInterval(second), latitude: 47 + second / 100_000,
            longitude: 8, altitude: 400, heartRate: heartRate(second), cadence: 85.5,
            distance: speed * second, speed: speed, power: nil)
    }
}

/// The demo's first run from 27 October 2026 on.
nonisolated private func demoRunActivity() -> SummarizedActivity? {
    (0..<7).lazy.compactMap {
        SummarizedActivity.sampleRun(on: GarminDate.day("2026-10-27").adding(days: $0))
    }
    .first
}

@Suite struct FITTests {
    @Test func roundTripsThroughTheWriter() throws {
        let activity = FITActivity(
            records: records(seconds: 20),
            laps: [
                FITActivity.Lap(
                    start: start, elapsed: 20, moving: 18, distance: 80, averageSpeed: 4,
                    averageHeartRate: 150, maxHeartRate: 160, ascent: 3, averagePower: 210)
            ],
            sets: [
                FITActivity.ExerciseSet(
                    start: start, duration: 45, repetitions: 8, weight: 80, isActive: true,
                    category: 28),
                FITActivity.ExerciseSet(start: start, duration: 90, isActive: false),
            ],
            timerEvents: [
                .init(time: start, isStart: true), .init(time: start + 20, isStart: false),
            ])
        let data = FITWriter.encode(activity)
        // A FIT file's checksum over everything, its own CRC included, is zero.
        #expect(FITWriter.crc([UInt8](data)) == 0)
        let decoded = try FITActivity(decoding: data)
        #expect(decoded.laps == activity.laps)
        #expect(decoded.sets == activity.sets)
        #expect(decoded.timerEvents == activity.timerEvents)
        #expect(decoded.records.count == activity.records.count)
        for (read, written) in zip(decoded.records, activity.records) {
            #expect(read.time == written.time)
            #expect(abs((read.latitude ?? 0) - (written.latitude ?? 0)) < 1e-6)
            #expect(read.heartRate == written.heartRate)
            #expect(read.cadence == written.cadence)
            #expect(read.distance == written.distance)
            #expect(read.altitude == written.altitude)
            #expect(read.power == nil)
        }
    }

    @Test func readsBigEndianCompressedAndDeveloperMessages() throws {
        var body: [UInt8] = []
        // Local 0: a big-endian record with a timestamp, heart rate and a developer field.
        body += [0x60, 0, 1, 0, 20, 2, 253, 4, 0x86, 3, 1, 0x02, 1, 0, 2, 0]
        body += [0x00, 0, 0, 0x03, 0xE8, 120, 0xAA, 0xBB]
        // Local 1: heart rate only, sent with compressed timestamp headers.
        body += [0x41, 0, 0, 20, 0, 1, 3, 1, 0x02]
        body += [0x80 | 0x20 | 0x0A, 125]  // 1000 & 31 is 8, so 10 is two seconds later.
        body += [0x80 | 0x20 | 0x02, 0xFF]  // Back to 2: past the 32-second roll-over.
        let header: [UInt8] =
            [12, 0x10, 0, 0] + withUnsafeBytes(of: UInt32(body.count).littleEndian, Array.init)
            + Array(".FIT".utf8)
        let activity = try FITActivity(decoding: Data(header + body))
        #expect(activity.records.map(\.heartRate) == [120, 125, nil])
        #expect(
            activity.records.map { $0.time.timeIntervalSince(FITActivity.epoch) } == [
                1000, 1002, 1026,
            ])
    }

    @Test func rejectsWhatIsNotFIT() {
        #expect(throws: FITError.notFIT) { try FITActivity(decoding: Data("not a fit file".utf8)) }
        let truncated = Data([14, 0x10, 0, 0, 100, 0, 0, 0] + Array(".FIT".utf8) + [0, 0])
        #expect(throws: FITError.truncated) { try FITActivity(decoding: truncated) }
        let undefined = Data([12, 0x10, 0, 0, 1, 0, 0, 0] + Array(".FIT".utf8) + [0x03])
        #expect(throws: FITError.undefinedMessage(local: 3)) {
            try FITActivity(decoding: undefined)
        }
    }

    @Test func invalidValuesAreMissing() {
        #expect(FITBaseType.value(0xFF, type: 0x02) == nil)
        #expect(FITBaseType.value(0x7FFF_FFFF, type: 0x85) == nil)
        #expect(FITBaseType.value(0, type: 0x8C) == nil)
        #expect(FITBaseType.value(0xFFFF_FFFE, type: 0x85) == -2)
        #expect(FITBaseType.value(0x3F80_0000, type: 0x88) == 1)
        #expect(FITBaseType.value(0, type: 0x07) == nil)
        #expect(FITBaseType.size(0x89) == 8)
        #expect(FITBaseType.size(0x1F) == 0)
    }

    @Test func zipsAsGarminDoes() async throws {
        #expect(StoredZip.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
        let run = try #require(demoRunActivity())
        let file = try await client(DemoTransport()).downloadActivity(run.activityId)
        #expect(file.fileExtension == "fit")
        #expect(file.content == FITWriter.encode(.sample(of: run)))
    }
}

@Suite struct ActivityTrackTests {
    @Test func pausesAreLeftOut() {
        let clock = TimerClock(
            start: start,
            events: [
                .init(time: start + 10, isStart: false), .init(time: start + 40, isStart: true),
                .init(time: start + 50, isStart: false),
            ])
        #expect(clock.seconds(at: start + 5) == 5)
        #expect(clock.seconds(at: start + 20) == 10)
        #expect(clock.seconds(at: start + 45) == 15)
        // A stop without a start is no pause yet.
        #expect(clock.seconds(at: start + 60) == 30)
    }

    @Test func heartRateLevelsSpanTheRoute() {
        // Heart rate climbs from 120 to 180 over ten minutes.
        let track = ActivityTrack(
            FITActivity(records: records(seconds: 600) { 120 + Int($0 / 10) }), sport: .running,
            splitLength: 1000)
        #expect(track.heartRateRange == 120...180)
        let segments = track.segments(heartRateLevels: 6)
        #expect(segments.first?.zone == 0)
        #expect(segments.last?.zone == 5)
        #expect(segments.map(\.zone) == (0..<6).map(Optional.some))
        // Each stretch starts where the one before ends.
        for (before, after) in zip(segments, segments.dropFirst()) {
            #expect(before.points.last == after.points.first)
        }
    }

    @Test func aSteadyHeartRateHasNoLevels() {
        let track = ActivityTrack(
            FITActivity(records: records(seconds: 60)), sport: .running, splitLength: 1000)
        #expect(track.heartRateRange == nil)
        #expect(track.segments(heartRateLevels: 6).map(\.zone) == [nil])
    }

    @Test func splitsAreTimedAtEachBoundary() throws {
        var recorded = records(seconds: 625)
        // Climb 5 m over the first kilometre, with sub-metre noise that must not count.
        for index in recorded.indices {
            let second = Double(index)
            recorded[index].altitude =
                400 + min(5, second / 50) + (index.isMultiple(of: 2) ? 0.4 : 0)
        }
        let track = ActivityTrack(
            FITActivity(records: recorded), sport: .running, splitLength: 1000)
        #expect(track.splits.map(\.distance) == [1000, 1000, 500])
        #expect(track.splits.map(\.duration) == [250, 250, 125])
        #expect(track.splits.map(\.heartRate) == [150, 150, 150])
        let climb = try #require(track.splits.first?.ascent)
        #expect(climb > 4 && climb < 6)
        #expect(track.splits.last?.ascent == 0)
        #expect(track.splits.first?.speed == 4)
        #expect(track.duration == 625)
    }

    @Test func samplesAndRouteAreBounded() {
        let track = ActivityTrack(
            FITActivity(records: records(seconds: 3600)), sport: .running, splitLength: 1000)
        #expect(track.samples.count == ActivityTrack.maxSamples)
        #expect(track.route.count <= ActivityTrack.maxPoints + 1)
        #expect(track.route.last?.elapsed == 3600)
        // Running cadence is counted in steps, not strides.
        #expect(track.samples.first?.cadence == 171)
        #expect(track.has(\.heartRate))
        #expect(!track.has(\.power))
        #expect(track.sample(near: 1800)?.elapsed ?? 0 > 1790)
        #expect(track.point(near: 1800)?.elapsed ?? 0 > 1790)
        let ride = ActivityTrack(
            FITActivity(records: records(seconds: 60)), sport: .cycling, splitLength: 1000)
        #expect(ride.samples.first?.cadence == 85.5)
        #expect(ActivityTrack(FITActivity(), sport: .running, splitLength: 1000).samples.isEmpty)
    }

    @Test func routeSegmentsFollowHeartRateZones() throws {
        let zones = try #require(
            HeartRateZoneSet(
                HeartRateZones(
                    zone1Floor: 100, zone2Floor: 120, zone3Floor: 140, zone4Floor: 160,
                    zone5Floor: 180)))
        let recorded = records(seconds: 30) { $0 < 10 ? 130 : ($0 < 20 ? 150 : 170) }
        let track = ActivityTrack(
            FITActivity(records: recorded), sport: .running, splitLength: 1000)
        let segments = track.segments(zones: zones)
        #expect(segments.map(\.zone) == [1, 2, 3])
        // Each stretch begins where the one before ended.
        #expect(segments[0].points.last == segments[1].points.first)
        #expect(track.segments(zones: nil).map(\.zone) == [nil])
        let still = ActivityTrack(
            FITActivity(records: [records(seconds: 0)[0]]), sport: .running, splitLength: 1000)
        #expect(still.segments(zones: zones).count == 1)
    }
}

@Suite struct DemoRecordingTests {
    private let day = GarminDate.day("2026-10-27")

    @Test func demoIdsNameTheirActivities() throws {
        let run = try #require(demoRunActivity())
        #expect(SummarizedActivity.sample(id: run.activityId) == run)
        #expect(SummarizedActivity.sample(id: 99_000_000_000) == nil)
    }

    @Test func recordingsMatchTheirActivities() {
        let days = (0..<14).map { day.adding(days: $0) }
        let activities = days.flatMap(SummarizedActivity.sampleActivities)
        for activity in activities {
            let recording = FITActivity.sample(of: activity)
            #expect(!recording.records.isEmpty)
            let sport = Sport(typeKey: activity.activityType?.typeKey)
            let track = ActivityTrack(recording, sport: sport, splitLength: 1000)
            switch sport {
            case .strength:
                #expect(track.route.isEmpty)
                #expect(SetsCard.logged(track.sets).count == 12)
            default:
                #expect(!track.route.isEmpty)
                #expect(track.laps.count > 1)
                #expect(abs(track.duration - (activity.duration ?? 0)) <= 5)
            }
        }
        #expect(FITActivity.sample(of: SummarizedActivity(activityId: 1)).records.isEmpty)
    }
}

@Suite struct TrackLoadingTests {
    private func demoRun() throws -> Workout {
        try #require(demoRunActivity().flatMap(Workout.init))
    }

    private func model(
        _ recording: @escaping @Sendable (Int) async throws -> Data?
    ) -> TrainingModel {
        TrainingModel(
            fetch: { end, _ in .sample(endingOn: end) },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) },
            fetchRecording: recording)
    }

    @Test func loadsAndKeepsARecording() async throws {
        let workout = try demoRun()
        let run = try #require(SummarizedActivity.sample(id: workout.id))
        let model = model { _ in FITWriter.encode(.sample(of: run)) }
        await model.loadTrack(for: workout)
        guard case .loaded(let track) = model.tracks[workout.id] else {
            Issue.record("no track")
            return
        }
        #expect(!track.splits.isEmpty)
        await model.loadTrack(for: workout)
        #expect(model.tracks[workout.id] == .loaded(track))
    }

    @Test func manyRecordingsLoadAFewAtATime() async throws {
        let run = try demoRun()
        let activity = try #require(SummarizedActivity.sample(id: run.id))
        let data = FITWriter.encode(.sample(of: activity))
        let gauge = Gauge()
        let model = model { _ in
            await gauge.enter()
            try await Task.sleep(for: .milliseconds(20))
            await gauge.leave()
            return data
        }
        // Ten copies of the run under different ids.
        let runs = try (1...10).map { offset in
            var copy = activity
            copy.activityId = activity.activityId + offset
            return try #require(Workout(copy))
        }
        await model.loadTracks(for: runs, width: 3)
        #expect(runs.allSatisfy { model.route(of: $0) != nil })
        #expect(await gauge.most <= 3)
        #expect(await gauge.most >= 2)
    }

    /// How many downloads run at once, at most.
    private actor Gauge {
        private var current = 0
        private(set) var most = 0

        func enter() {
            current += 1
            most = max(most, current)
        }

        func leave() {
            current -= 1
        }
    }

    @Test func activitiesWithoutARecording() async throws {
        let workout = try demoRun()
        let manual = model { _ in nil }
        await manual.loadTrack(for: workout)
        #expect(manual.tracks[workout.id] == .unavailable)
        let garbled = model { _ in Data("<gpx/>".utf8) }
        await garbled.loadTrack(for: workout)
        #expect(garbled.tracks[workout.id] == .unavailable)
    }

    @Test func aFailedDownloadCanBeRetried() async throws {
        let workout = try demoRun()
        let attempts = Attempts()
        let model = model { _ in
            if await attempts.next() == 1 {
                throw Problem.offline
            }
            return FITWriter.encode(FITActivity(records: records(seconds: 10)))
        }
        await model.loadTrack(for: workout)
        #expect(model.tracks[workout.id] == .failed(.offline))
        await model.loadTrack(for: workout)
        guard case .loaded = model.tracks[workout.id] else {
            Issue.record("the retry did not load")
            return
        }
        let cancelled = self.model { _ in throw CancellationError() }
        await cancelled.loadTrack(for: workout)
        #expect(cancelled.tracks[workout.id] == nil)
    }
}

/// Counts calls.
private actor Attempts {
    var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

@Suite struct ActivityPresentationTests {
    private let sample = ActivityTrack.Sample(
        elapsed: 60, distance: 250, heartRate: 151.6, speed: 1000.0 / 300, altitude: 100,
        cadence: 172, power: 250)

    @Test func measuresInTheUsersUnits() {
        let pace = TrackMeasure.pace.value(sample, sport: .running) ?? 0
        #expect(abs(pace + (Format.usesMiles ? 8.0467 : 5)) < 1e-3)
        #expect(
            TrackMeasure.pace.format(pace, sport: .running)
                == (Format.usesMiles ? "8:03 /mi" : "5:00 /km"))
        #expect(TrackMeasure.pace.axisLabel(-5, sport: .running) == "5:00")
        let slow = ActivityTrack.Sample(
            elapsed: 0, distance: nil, heartRate: nil, speed: 0.5, altitude: nil, cadence: nil,
            power: nil)
        #expect(TrackMeasure.pace.value(slow, sport: .running) == nil)
        #expect(TrackMeasure.pace.value(slow, sport: .swimming) != nil)
        // 3.33 m/s is 12 km/h, or 7.46 mph.
        let speed = TrackMeasure.pace.value(sample, sport: .cycling) ?? 0
        #expect(abs(speed - (Format.usesMiles ? 7.4565 : 12)) < 1e-3)
        #expect(TrackMeasure.heartRate.format(151.6, sport: .running) == "152 bpm")
        #expect(TrackMeasure.power.format(250, sport: .cycling) == "250 W")
        #expect(TrackMeasure.cadence.format(86, sport: .cycling) == "86 rpm")
        #expect(TrackMeasure.elevation.value(sample, sport: .running) != nil)
        for measure in TrackMeasure.allCases {
            #expect(!measure.title(for: .running).isEmpty)
            #expect(!measure.format(1, sport: .cycling).isEmpty)
            _ = measure.color
        }
        #expect(TrackMeasure.pace.title(for: .cycling) != TrackMeasure.pace.title(for: .running))
    }

    @Test func chartDomainsIgnoreOutliers() {
        let values = Array(repeating: 150.0, count: 98) + [40, 250]
        let domain = TrackChart.domain(values)
        #expect(domain.lowerBound > 100 && domain.upperBound < 200)
        #expect(TrackChart.domain([]) == 0...1)
        #expect(TrackChart.domain([5, 5]).lowerBound == 5)
    }

    @Test func setsAndZones() {
        let set = FITActivity.ExerciseSet(
            start: nil, duration: 45, repetitions: 8, weight: 80, isActive: true, category: 28)
        #expect(SetsCard.detail(set).hasPrefix("8 × "))
        #expect(SetsCard.detail(set).hasSuffix("0:45"))
        #expect(
            SetsCard.logged([set, FITActivity.ExerciseSet(isActive: true), .init(isActive: false)])
                .count == 1)
        #expect(ExerciseCategory.name(28) == String(localized: "Squat"))
        #expect(ExerciseCategory.name(nil) == nil)
        #expect(ExerciseCategory.name(9999) == nil)
        #expect(ZoneStyle.color(zone: nil, fallback: .mint) == .mint)
        #expect(ZoneStyle.color(zone: 99, fallback: .mint).hex == ZoneStyle.colors.last?.hex)
    }

    @Test func tilesShowTheLatestDay() throws {
        let today = GarminDate.today()
        var days = (0..<3).map { DayHealth(date: today.adding(days: $0 - 2)) }
        days[1].restingHeartRate = 47
        days[2].sleep = SleepNight(total: 27_000, deep: 0, light: 0, rem: 0, awake: 0, score: 80)
        days[1].intensityMinutes = 60
        let history = HealthHistory(days: days)
        let heart = try #require(Metric.restingHeartRate.tile(of: history))
        #expect(heart.value == "47")
        #expect(heart.detail == String(localized: "Yesterday"))
        #expect(Metric.sleep.tile(of: history)?.detail == String(localized: "Last night"))
        #expect(Metric.steps.tile(of: history) == nil)
        #expect(Metric.intensityMinutes.tile(of: history)?.value == 140.formatted())
        #expect(Metric.when(today, metric: .steps) == String(localized: "Today"))
        #expect(!Metric.when(today.adding(days: -3), metric: .steps).isEmpty)
        for metric in Metric.allCases {
            #expect(!metric.shortTitle.isEmpty)
            #expect(metric.number(of: DayHealth.sample(for: today)) != nil)
        }
    }
}

@Suite struct ActivityLogTests {
    private func workout(_ id: Int, on date: String) throws -> Workout {
        try #require(
            Workout(
                SummarizedActivity(
                    activityId: id,
                    startTimeLocal: (try? GarminTime(hour: 7)).map {
                        LocalDateTime(date: .day(date), time: $0)
                    },
                    activityType: ActivityType(typeKey: "running"), duration: 1800)))
    }

    @Test func emptyDaysHaveADash() throws {
        let days = ["2026-10-30", "2026-10-29", "2026-10-28"].map(GarminDate.day)
        let table = ActivityLogTable(
            workouts: [
                try workout(1, on: "2026-10-30"), try workout(2, on: "2026-10-30"),
                try workout(3, on: "2026-10-28"),
            ],
            days: days)
        let rows = table.rows.map { row in
            switch row {
            case .activity(let workout, let showsDay): "\(workout.id) \(showsDay)"
            case .rest(let date): "\(date)"
            }
        }
        #expect(rows == ["1 true", "2 false", "2026-10-29", "3 true"])
    }
}
