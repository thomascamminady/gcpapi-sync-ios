import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

@Suite("Workout from a Garmin activity")
struct BlackBoxWorkoutTests {
    static let start = Date(timeIntervalSince1970: 1_761_030_954)

    static func activity(typeKey: String = "running") throws -> SummarizedActivity {
        var activity = SummarizedActivity(activityId: 21_087_654_321)
        activity.activityName = "Morning Run"
        activity.activityType = ActivityType(typeId: 1, typeKey: typeKey, parentTypeId: 17)
        activity.startTimeLocal = LocalDateTime(
            date: GarminDate.day("2026-10-21"),
            time: try GarminTime(hour: 7, minute: 15, second: 54))
        activity.startTimeGMT = start
        activity.beginTimestamp = start
        activity.duration = 3012.5
        activity.distance = 10_234.5
        activity.averageSpeed = 3.397
        activity.averageHR = 148
        activity.maxHR = 176
        activity.elevationGain = 87
        activity.calories = 712
        activity.avgPower = 291
        activity.normPower = 302
        activity.activityTrainingLoad = 143.2
        activity.aerobicTrainingEffect = 3.4
        activity.anaerobicTrainingEffect = 1.2
        activity.trainingEffectLabel = "AEROBIC_BASE"
        activity.aerobicTrainingEffectMessage = "IMPROVING_AEROBIC_BASE_8"
        activity.anaerobicTrainingEffectMessage = "NO_ANAEROBIC_BENEFIT_0"
        activity.locationName = "Zürich"
        return activity
    }

    @Test("Every field is taken from the activity")
    func fields() throws {
        var activity = try Self.activity()
        activity.averageRunningCadenceInStepsPerMinute = 171
        let workout = try #require(Workout(activity))
        #expect(workout.id == 21_087_654_321)
        #expect(workout.name == "Morning Run")
        #expect(workout.typeKey == "running")
        #expect(workout.sport == .running)
        #expect(workout.date == GarminDate.day("2026-10-21"))
        #expect(workout.start == Self.start)
        #expect(workout.duration == 3012.5)
        #expect(workout.distance == 10_234.5)
        #expect(workout.averageSpeed == 3.397)
        #expect(workout.averageHeartRate == 148)
        #expect(workout.maxHeartRate == 176)
        #expect(workout.elevationGain == 87)
        #expect(workout.calories == 712)
        #expect(workout.averagePower == 291)
        #expect(workout.normalizedPower == 302)
        #expect(workout.cadence == 171)
        #expect(workout.trainingLoad == 143.2)
        #expect(workout.aerobicEffect == 3.4)
        #expect(workout.anaerobicEffect == 1.2)
        #expect(workout.primaryBenefit == "AEROBIC_BASE")
        #expect(workout.aerobicMessage == "IMPROVING_AEROBIC_BASE_8")
        #expect(workout.anaerobicMessage == "NO_ANAEROBIC_BENEFIT_0")
        #expect(workout.location == "Zürich")
    }

    @Test(
        "The sport follows the activity type",
        arguments: [
            "running", "trail_running", "road_biking", "lap_swimming", "walking",
            "strength_training", "yoga",
        ])
    func sport(typeKey: String) throws {
        let workout = try #require(Workout(try Self.activity(typeKey: typeKey)))
        #expect(workout.typeKey == typeKey)
        #expect(workout.sport == Sport(typeKey: typeKey))
    }

    @Test("Cycling cadence is in revolutions a minute")
    func cyclingCadence() throws {
        var activity = try Self.activity(typeKey: "road_biking")
        activity.averageBikingCadenceInRevPerMinute = 88
        #expect(Workout(activity)?.cadence == 88)
    }

    @Test("Without a duration there is no workout")
    func noDuration() throws {
        var activity = try Self.activity()
        activity.duration = nil
        #expect(Workout(activity) == nil)
    }

    @Test("Without a start there is no workout")
    func noStart() throws {
        var activity = try Self.activity()
        activity.startTimeLocal = nil
        activity.startTimeGMT = nil
        activity.beginTimestamp = nil
        #expect(Workout(activity) == nil)
    }

    @Test("Missing numbers stay missing")
    func missingNumbers() throws {
        var activity = SummarizedActivity(activityId: 7)
        activity.startTimeLocal = try Self.activity().startTimeLocal
        activity.duration = 600
        let workout = try #require(Workout(activity))
        #expect(workout.id == 7)
        #expect(workout.duration == 600)
        #expect(workout.distance == nil)
        #expect(workout.averageSpeed == nil)
        #expect(workout.averageHeartRate == nil)
        #expect(workout.maxHeartRate == nil)
        #expect(workout.elevationGain == nil)
        #expect(workout.calories == nil)
        #expect(workout.averagePower == nil)
        #expect(workout.normalizedPower == nil)
        #expect(workout.cadence == nil)
        #expect(workout.trainingLoad == nil)
        #expect(workout.aerobicEffect == nil)
        #expect(workout.anaerobicEffect == nil)
        #expect(workout.primaryBenefit == nil)
        #expect(workout.location == nil)
        #expect(workout.heartRateZones.isEmpty)
        #expect(workout.powerZones.isEmpty)
    }

    @Test("Seconds in heart rate zones 1 to 5")
    func heartRateZones() throws {
        var activity = try Self.activity()
        activity.hrTimeInZone1 = 300
        activity.hrTimeInZone2 = 900
        activity.hrTimeInZone3 = 1200
        activity.hrTimeInZone4 = 500
        activity.hrTimeInZone5 = 112.5
        #expect(Workout(activity)?.heartRateZones == [300, 900, 1200, 500, 112.5])
    }

    @Test("Seconds in power zones 1 to 7")
    func powerZones() throws {
        var activity = try Self.activity(typeKey: "road_biking")
        activity.powerTimeInZone1 = 10
        activity.powerTimeInZone2 = 20
        activity.powerTimeInZone3 = 30
        activity.powerTimeInZone4 = 40
        activity.powerTimeInZone5 = 50
        activity.powerTimeInZone6 = 60
        activity.powerTimeInZone7 = 70
        #expect(Workout(activity)?.powerZones == [10, 20, 30, 40, 50, 60, 70])
    }
}

@Suite("TrackBuilder")
struct BlackBoxTrackBuilderTests {
    @Test("Builds the track that decoding and analyzing gives", arguments: [1000, 1609.344])
    func sameTrack(splitLength: Double) async throws {
        var activity = RecordingRun(seconds: 2400, pause: 500...700, cadence: 80).activity
        var random = RecordingRandom(seed: 13_000)
        activity.laps = RecordingFixtures.randomLaps(3, using: &random)
        activity.sets = RecordingFixtures.randomSets(2, using: &random)
        let data = FITWriter.encode(activity)
        let built = try await TrackBuilder.track(
            from: data, sport: .running, splitLength: splitLength)
        let direct = ActivityTrack(
            try FITActivity(decoding: data), sport: .running, splitLength: splitLength)
        #expect(built.samples == direct.samples)
        #expect(built.route == direct.route)
        #expect(built.splits == direct.splits)
        #expect(built.laps == direct.laps)
        #expect(built.sets == direct.sets)
        #expect(built.duration == direct.duration)
        #expect(built.duration == 2199)
        #expect(!built.splits.isEmpty)
    }

    @Test("Data that is not FIT is rejected")
    func notFIT() async {
        do {
            _ = try await TrackBuilder.track(
                from: Data(RecordingBytes.ascii("<html>Not found</html>, really not FIT")),
                sport: .running, splitLength: 1000)
            Issue.record("expected an error")
        } catch {
            #expect(error == .notFIT)
        }
    }

    @Test("A truncated file is rejected")
    func truncated() async {
        let data = FITWriter.encode(RecordingRun(seconds: 100).activity)
        do {
            _ = try await TrackBuilder.track(
                from: data.prefix(data.count / 2), sport: .running, splitLength: 1000)
            Issue.record("expected an error")
        } catch {
            #expect(error == .truncated)
        }
    }
}

@Suite("Demo recordings")
struct BlackBoxSampleRecordingTests {
    static func activity(typeKey: String) throws -> SummarizedActivity {
        var activity = try BlackBoxWorkoutTests.activity(typeKey: typeKey)
        activity.duration = 1800
        activity.elapsedDuration = 1800
        activity.movingDuration = 1800
        let distance = typeKey == "road_biking" ? 15_000.0 : 5000
        activity.distance = distance
        activity.averageSpeed = distance / 1800
        return activity
    }

    /// Metres between two coordinates on a sphere of the Earth's mean radius.
    static func metres(_ first: FITActivity.Record, _ second: FITActivity.Record) -> Double? {
        guard let lat1 = first.latitude, let lon1 = first.longitude, let lat2 = second.latitude,
            let lon2 = second.longitude
        else { return nil }
        let radians = Double.pi / 180
        let deltaLat = (lat2 - lat1) * radians
        let deltaLon = (lon2 - lon1) * radians
        let chord =
            sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1 * radians) * cos(lat2 * radians) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * 6_371_000 * asin(min(1, sqrt(chord)))
    }

    @Test("One record every five seconds", arguments: ["running", "road_biking", "walking"])
    func everyFiveSeconds(typeKey: String) throws {
        let records = FITActivity.sample(of: try Self.activity(typeKey: typeKey)).records
        try #require(records.count >= 2)
        let gaps = zip(records, records.dropFirst()).map { $1.time.timeIntervalSince($0.time) }
        #expect(gaps.allSatisfy { abs($0 - 5) < 1e-9 }, "\(Set(gaps))")
    }

    @Test("Runs and rides are loops with hills", arguments: ["running", "road_biking"])
    func loopWithHills(typeKey: String) throws {
        let records = FITActivity.sample(of: try Self.activity(typeKey: typeKey)).records
        let first = try #require(records.first)
        let gaps = records.compactMap { Self.metres(first, $0) }
        let away = try #require(gaps.firstIndex { $0 > 500 }, "the route leaves its start")
        let back = try #require(gaps.suffix(from: away).min())
        #expect(back < 150, "the loop comes back to within \(back) m of its start")
        let altitudes = records.compactMap(\.altitude)
        let low = try #require(altitudes.min())
        let high = try #require(altitudes.max())
        #expect(high - low > 1)
        let track = ActivityTrack(
            FITActivity.sample(of: try Self.activity(typeKey: typeKey)),
            sport: Sport(typeKey: typeKey), splitLength: 1000)
        #expect(!track.route.isEmpty)
        #expect(!track.splits.isEmpty)
        #expect(track.has(\.heartRate))
    }

    @Test("Strength training has sets")
    func strengthSets() throws {
        let fit = FITActivity.sample(of: try Self.activity(typeKey: "strength_training"))
        #expect(!fit.sets.isEmpty)
        let hasActiveSet = fit.sets.contains(where: \.isActive)
        #expect(hasActiveSet)
        #expect(!SetsCard.logged(fit.sets).isEmpty)
    }

    @Test(
        "Demo recordings survive the FIT writer",
        arguments: ["running", "road_biking", "strength_training"])
    func roundTrip(typeKey: String) throws {
        let fit = FITActivity.sample(of: try Self.activity(typeKey: typeKey))
        let decoded = try FITActivity(decoding: FITWriter.encode(fit))
        #expect(decoded.records.count == fit.records.count)
        #expect(decoded.sets.count == fit.sets.count)
        #expect(decoded.laps.count == fit.laps.count)
        #expect(decoded.timerEvents.count == fit.timerEvents.count)
    }
}
