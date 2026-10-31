import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A steady recording: one record a second at a constant speed, distance from 0, on a circle
/// around 47° N 8° E. A pause (in wall-clock seconds) has no records and timer events around it.
nonisolated struct RecordingRun {
    var seconds = 600
    var speed = 4.0
    var pause: ClosedRange<Int>?
    /// By second of timer time.
    var heartRate: (Int) -> Int? = { _ in 150 }
    var altitude: (Int) -> Double? = { _ in 100 }
    var cadence: Double?
    var power: Int?
    var positions: (Int) -> Bool = { _ in true }

    var pauseLength: Int { pause.map { $0.upperBound - $0.lowerBound } ?? 0 }

    /// The last second of timer time.
    var timerSeconds: Int { seconds - 1 - pauseLength }

    var activity: FITActivity {
        var records: [FITActivity.Record] = []
        for wall in 0..<seconds {
            if let pause, wall > pause.lowerBound, wall <= pause.upperBound {
                continue
            }
            let timer = pause.map { wall > $0.upperBound ? wall - pauseLength : wall } ?? wall
            let angle = Double(timer) / Double(max(timerSeconds, 1)) * 2 * .pi
            let positioned = positions(timer)
            records.append(
                FITActivity.Record(
                    time: RecordingFixtures.start + Double(wall),
                    latitude: positioned ? 47 + 0.01 * sin(angle) : nil,
                    longitude: positioned ? 8 + 0.01 * cos(angle) : nil,
                    altitude: altitude(timer), heartRate: heartRate(timer), cadence: cadence,
                    distance: speed * Double(timer), speed: speed, power: power))
        }
        var events = [FITActivity.TimerEvent(time: RecordingFixtures.start, isStart: true)]
        if let pause {
            events.append(
                FITActivity.TimerEvent(
                    time: RecordingFixtures.start + Double(pause.lowerBound), isStart: false))
            events.append(
                FITActivity.TimerEvent(
                    time: RecordingFixtures.start + Double(pause.upperBound), isStart: true))
        }
        return FITActivity(records: records, timerEvents: events)
    }

    static func withHeartRate(seconds: Int = 600, _ heartRate: @escaping (Int) -> Int?) -> Self {
        var run = Self(seconds: seconds)
        run.heartRate = heartRate
        return run
    }

    static func withAltitude(_ altitude: @escaping (Int) -> Double?) -> Self {
        var run = Self()
        run.altitude = altitude
        return run
    }

    static func withPositions(_ positions: @escaping (Int) -> Bool) -> Self {
        var run = Self()
        run.positions = positions
        return run
    }

    func track(sport: Sport = .running, splitLength: Double = 1000) -> ActivityTrack {
        ActivityTrack(activity, sport: sport, splitLength: splitLength)
    }
}

@Suite("ActivityTrack samples")
struct BlackBoxActivityTrackSampleTests {
    @Test("An empty recording has nothing to show")
    func empty() {
        let track = ActivityTrack(FITActivity(), sport: .running, splitLength: 1000)
        #expect(track.samples.isEmpty)
        #expect(track.route.isEmpty)
        #expect(track.splits.isEmpty)
        #expect(track.laps.isEmpty)
        #expect(track.sets.isEmpty)
        #expect(track.duration == 0)
        #expect(track.sample(near: 0) == nil)
        #expect(track.point(near: 0) == nil)
        #expect(track.segments(zones: nil).isEmpty)
        #expect(!track.has(\.heartRate))
        #expect(!track.has(\.speed))
    }

    @Test("The limits are positive")
    func limits() {
        #expect(ActivityTrack.maxSamples > 0)
        #expect(ActivityTrack.maxPoints > 0)
    }

    @Test("Duration is timer time from the first record to the last", arguments: [false, true])
    func duration(paused: Bool) {
        let run = RecordingRun(seconds: paused ? 700 : 600, pause: paused ? 300...400 : nil)
        #expect(run.track().duration == 599)
    }

    @Test("Duration starts at the first record, not at the timer start")
    func durationFromFirstRecord() {
        var activity = RecordingRun().activity
        activity.records.removeFirst(100)
        let track = ActivityTrack(activity, sport: .running, splitLength: 1000)
        #expect(track.duration == 499)
    }

    @Test(
        "Samples are capped, ordered and unique",
        arguments: [1, 2, 3, 10, 100, 1000, 5000, 20_000, 40_000])
    func capped(count: Int) {
        let track = RecordingRun(seconds: count).track()
        #expect(track.duration == Double(count - 1))
        #expect(track.samples.count <= ActivityTrack.maxSamples)
        #expect(track.samples.count >= min(count, 2))
        let elapsed = track.samples.map(\.elapsed)
        #expect(zip(elapsed, elapsed.dropFirst()).allSatisfy { $0 < $1 })
        #expect(elapsed.allSatisfy { $0 >= 0 })
        #expect(Set(track.samples.map(\.id)).count == track.samples.count)
    }

    @Test("Samples of constant values are those values")
    func constant() throws {
        let run = RecordingRun(seconds: 3000, cadence: 80, power: 210)
        let track = run.track(sport: .cycling)
        try #require(!track.samples.isEmpty)
        for sample in track.samples {
            #expect(RecordingFixtures.close(sample.heartRate, 150, within: 1e-9))
            #expect(RecordingFixtures.close(sample.speed, 4, within: 1e-9))
            #expect(RecordingFixtures.close(sample.altitude, 100, within: 1e-9))
            #expect(RecordingFixtures.close(sample.cadence, 80, within: 1e-9))
            #expect(RecordingFixtures.close(sample.power, 210, within: 1e-9))
        }
    }

    @Test("Samples average the records of their slice of time")
    func averages() {
        let count = 10 * ActivityTrack.maxSamples
        let run = RecordingRun.withHeartRate(seconds: count) { $0.isMultiple(of: 2) ? 100 : 200 }
        let rates = run.track().samples.compactMap(\.heartRate)
        #expect(rates.allSatisfy { (100...200).contains($0) })
        let averaged = rates.filter { (140...160).contains($0) }.count
        #expect(Double(averaged) >= 0.9 * Double(rates.count), "\(averaged) of \(rates.count)")
    }

    @Test("Samples stay within the recorded values", arguments: 0..<8)
    func withinRange(seed: Int) throws {
        var random = RecordingRandom(seed: UInt64(seed) + 7000)
        let records = RecordingFixtures.randomRecords(random.int(50...5000), using: &random)
        let track = ActivityTrack(
            FITActivity(records: records), sport: .cycling, splitLength: 1000)
        let first = try #require(records.first?.time)
        let last = try #require(records.last?.time)
        #expect(abs(track.duration - last.timeIntervalSince(first)) < 1e-9)
        let ranges: [(KeyPath<ActivityTrack.Sample, Double?>, [Double])] = [
            (\.heartRate, records.compactMap(\.heartRate).map(Double.init)),
            (\.altitude, records.compactMap(\.altitude)),
            (\.speed, records.compactMap(\.speed)),
            (\.power, records.compactMap(\.power).map(Double.init)),
            (\.cadence, records.compactMap(\.cadence)),
        ]
        for (path, values) in ranges {
            let low = try #require(values.min())
            let high = try #require(values.max())
            #expect(track.has(path))
            for value in track.samples.compactMap({ $0[keyPath: path] }) {
                #expect(value >= low - 1e-9 && value <= high + 1e-9)
            }
        }
        let distances = track.samples.compactMap(\.distance)
        #expect(zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
    }

    @Test("Sample times leave out pauses")
    func pausesLeaveNoGap() throws {
        let track = RecordingRun(seconds: 1600, pause: 600...1000).track()
        #expect(track.duration == 1199)
        let elapsed = track.samples.map(\.elapsed)
        let last = try #require(elapsed.last)
        #expect(last <= 1199 + 1e-9)
        let gaps = zip(elapsed, elapsed.dropFirst()).map { $1 - $0 }
        #expect((gaps.max() ?? 0) < 100, "no gap of the 400 s pause")
        let distances = track.samples.compactMap(\.distance)
        #expect(zip(distances, distances.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
    }

    @Test(
        "Cadence is steps a minute on foot, revolutions on a bike",
        arguments: [(Sport.running, 2.0), (.walking, 2), (.cycling, 1)])
    func cadence(sport: Sport, factor: Double) throws {
        let track = RecordingRun(seconds: 300, cadence: 85).track(sport: sport)
        let cadences = track.samples.compactMap(\.cadence)
        try #require(!cadences.isEmpty)
        #expect(cadences.allSatisfy { abs($0 - 85 * factor) < 1e-9 }, "\(cadences.prefix(3))")
    }

    @Test("has tells which measurements were recorded")
    func has() {
        let plain = RecordingRun.withAltitude { _ in nil }.track()
        #expect(plain.has(\.heartRate))
        #expect(plain.has(\.distance))
        #expect(!plain.has(\.power))
        #expect(!plain.has(\.cadence))
        #expect(!plain.has(\.altitude))
        let full = RecordingRun(cadence: 88, power: 250).track()
        #expect(full.has(\.power))
        #expect(full.has(\.cadence))
        #expect(full.has(\.altitude))
        let noHeart = RecordingRun.withHeartRate { _ in nil }.track()
        #expect(!noHeart.has(\.heartRate))
    }

    @Test("sample(near:) is the nearest sample")
    func sampleNear() throws {
        let track = RecordingRun(seconds: 2000).track()
        let first = try #require(track.samples.first)
        let last = try #require(track.samples.last)
        #expect(track.sample(near: -500) == first)
        #expect(track.sample(near: last.elapsed + 1e6) == last)
        for (before, after) in zip(track.samples, track.samples.dropFirst()) {
            let gap = after.elapsed - before.elapsed
            #expect(track.sample(near: before.elapsed) == before)
            #expect(track.sample(near: before.elapsed + 0.25 * gap) == before)
            #expect(track.sample(near: before.elapsed + 0.75 * gap) == after)
        }
    }
}

@Suite("ActivityTrack splits and laps")
struct BlackBoxActivityTrackSplitTests {
    @Test(
        "Splits add up to the recorded distance and timer time",
        arguments: [1000, 1609.344], [false, true])
    func splitsAddUp(splitLength: Double, paused: Bool) throws {
        let run = RecordingRun(seconds: paused ? 700 : 600, pause: paused ? 300...400 : nil)
        let track = run.track(splitLength: splitLength)
        let total = 4.0 * 599
        let splits = track.splits
        #expect(splits.count == Int((total / splitLength).rounded(.up)))
        #expect(abs(splits.map(\.distance).reduce(0, +) - total) < 1e-6)
        #expect(abs(splits.map(\.duration).reduce(0, +) - track.duration) < 1e-6)
        #expect(splits.map(\.number) == Array(1...splits.count))
        #expect(Set(splits.map(\.id)).count == splits.count)
        for split in splits.dropLast() {
            #expect(abs(split.distance - splitLength) <= 4, "\(split.distance)")
            #expect(abs(split.duration - splitLength / 4) <= 1, "\(split.duration)")
        }
        let last = try #require(splits.last)
        #expect(last.distance > 0 && last.distance <= splitLength + 4)
        for split in splits {
            #expect(abs(split.speed - split.distance / split.duration) < 1e-9)
            #expect(RecordingFixtures.close(split.heartRate, 150, within: 1e-9))
            #expect(abs(split.ascent) < 1e-9)
        }
    }

    @Test("Split times leave out pauses")
    func pausesExcluded() {
        let track = RecordingRun(seconds: 700, pause: 300...400).track()
        #expect(track.splits.map(\.distance) == [1000, 1000, 396])
        let durations = track.splits.map(\.duration)
        let expected: [Double] = [250, 250, 99]
        #expect(durations.count == 3)
        for (duration, want) in zip(durations, expected) {
            #expect(abs(duration - want) <= 1, "\(durations)")
        }
    }

    @Test("A split's heart rate is its average")
    func heartRate() throws {
        let run = RecordingRun.withHeartRate(seconds: 1000) { $0 < 250 ? 100 : 160 }
        let splits = run.track().splits
        try #require(splits.count == 4)
        #expect(RecordingFixtures.close(splits[0].heartRate, 100, within: 1))
        #expect(RecordingFixtures.close(splits[1].heartRate, 160, within: 1))
        #expect(RecordingFixtures.close(splits[3].heartRate, 160, within: 1e-9))
        let none = RecordingRun.withHeartRate { _ in nil }.track().splits
        #expect(!none.isEmpty)
        #expect(none.allSatisfy { $0.heartRate == nil })
    }

    @Test("Ascent counts climbing only")
    func ascent() throws {
        let climb = RecordingRun.withAltitude { 100 + 0.5 * Double(min($0, 300)) }.track()
        let total = climb.splits.map(\.ascent).reduce(0, +)
        #expect(climb.splits.allSatisfy { $0.ascent >= 0 })
        #expect(total <= 150 + 1e-6 && total >= 145, "\(total)")
        let first = try #require(climb.splits.first)
        #expect(first.ascent >= 115 && first.ascent <= 125 + 1e-6, "\(first.ascent)")
        let descent = RecordingRun.withAltitude { 400 - 0.5 * Double($0) }.track()
        #expect(descent.splits.allSatisfy { abs($0.ascent) < 1e-9 })
        let hills = RecordingRun.withAltitude { 100 + 20 * sin(Double($0) / 30) }.track()
        let variation = (1..<600).map { second in
            max(0, 20 * sin(Double(second) / 30) - 20 * sin(Double(second - 1) / 30))
        }
        let hillTotal = hills.splits.map(\.ascent).reduce(0, +)
        #expect(hillTotal <= variation.reduce(0, +) + 1e-6)
        #expect(hillTotal > 0)
    }

    @Test("Without distance there are no splits")
    func noDistance() {
        var activity = RecordingRun.withPositions { _ in false }.activity
        for index in activity.records.indices {
            activity.records[index].distance = nil
            activity.records[index].speed = nil
        }
        let track = ActivityTrack(activity, sport: .running, splitLength: 1000)
        #expect(track.splits.isEmpty)
        #expect(!track.samples.isEmpty)
    }

    @Test("Laps and sets are passed through", arguments: 0..<6)
    func passThrough(seed: Int) {
        let activity = RecordingFixtures.randomActivity(seed: UInt64(seed) + 8000)
        let track = ActivityTrack(activity, sport: .strength, splitLength: 1000)
        #expect(track.laps == activity.laps)
        #expect(track.sets == activity.sets)
    }

    static func autoLaps(_ track: ActivityTrack) -> [FITActivity.Lap] {
        var start = RecordingFixtures.start
        return track.splits.map { split in
            defer { start += split.duration }
            return FITActivity.Lap(
                start: start, elapsed: split.duration, moving: split.duration,
                distance: split.distance, averageSpeed: split.speed, averageHeartRate: 150,
                maxHeartRate: 150, ascent: 0)
        }
    }

    @Test("Automatic laps of a kilometre or mile repeat the splits", arguments: [1000, 1609.344])
    func autoLapsRepeat(splitLength: Double) {
        let run = RecordingRun(seconds: 1300)
        let plain = run.track(splitLength: splitLength)
        var activity = run.activity
        activity.laps = Self.autoLaps(plain)
        let track = ActivityTrack(activity, sport: .running, splitLength: splitLength)
        #expect(track.laps.count == track.splits.count)
        #expect(track.lapsRepeatSplits)
    }

    @Test("One lap of the whole run does not repeat the splits")
    func oneLap() {
        var activity = RecordingRun(seconds: 1300).activity
        activity.laps = [
            FITActivity.Lap(
                start: RecordingFixtures.start, elapsed: 1299, moving: 1299, distance: 5196,
                averageSpeed: 4)
        ]
        #expect(!ActivityTrack(activity, sport: .running, splitLength: 1000).lapsRepeatSplits)
    }

    @Test("Interval laps do not repeat the splits")
    func intervalLaps() {
        var activity = RecordingRun(seconds: 1300).activity
        activity.laps = (0..<13).map { index in
            FITActivity.Lap(
                start: RecordingFixtures.start + Double(100 * index), elapsed: 100, moving: 100,
                distance: 400, averageSpeed: 4)
        }
        #expect(!ActivityTrack(activity, sport: .running, splitLength: 1000).lapsRepeatSplits)
    }

    @Test("Kilometre laps do not repeat mile splits")
    func kilometreLapsMileSplits() {
        let run = RecordingRun(seconds: 2000)
        var activity = run.activity
        activity.laps = Self.autoLaps(run.track(splitLength: 1000))
        #expect(!ActivityTrack(activity, sport: .running, splitLength: 1609.344).lapsRepeatSplits)
    }
}

@Suite("ActivityTrack route and segments")
struct BlackBoxActivityTrackRouteTests {
    /// Zone by stretch of timer seconds: 110, 130, 150, 168 or 182 bpm.
    static let rates = [110, 130, 150, 168, 182]

    @Test("The route is ordered and on the recorded positions", arguments: [2, 10, 1000, 30_000])
    func ordered(count: Int) {
        let track = RecordingRun(seconds: count).track()
        let route = track.route
        #expect(route.count <= count)
        #expect(route.count >= 2)
        let elapsed = route.map(\.elapsed)
        #expect(zip(elapsed, elapsed.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(elapsed.allSatisfy { $0 >= 0 && $0 <= track.duration + 1e-9 })
        #expect(route.allSatisfy { abs($0.latitude - 47) <= 0.01 + 1e-9 })
        #expect(route.allSatisfy { abs($0.longitude - 8) <= 0.01 + 1e-9 })
        #expect(route.allSatisfy { $0.heartRate == 150 })
    }

    @Test("Without positions there is no route")
    func noPositions() {
        let track = RecordingRun.withPositions { _ in false }.track()
        #expect(track.route.isEmpty)
        #expect(track.point(near: 10) == nil)
        #expect(track.segments(zones: try? RecordingFixtures.zones()).isEmpty)
        #expect(!track.samples.isEmpty)
    }

    @Test("Records without a position are left out of the route")
    func partialPositions() {
        let track = RecordingRun.withPositions { $0 < 300 }.track()
        #expect(!track.route.isEmpty)
        #expect(track.route.allSatisfy { $0.elapsed <= 300 + 1e-9 })
        #expect(track.route.allSatisfy { $0.latitude >= 47 - 1e-9 })
    }

    @Test("point(near:) is the nearest route point")
    func pointNear() throws {
        let track = RecordingRun(seconds: 3000).track()
        let first = try #require(track.route.first)
        let last = try #require(track.route.last)
        #expect(track.point(near: -100) == first)
        #expect(track.point(near: last.elapsed + 1e6) == last)
        for (before, after) in zip(track.route, track.route.dropFirst())
        where after.elapsed > before.elapsed {
            let gap = after.elapsed - before.elapsed
            #expect(track.point(near: before.elapsed + 0.25 * gap) == before)
            #expect(track.point(near: before.elapsed + 0.75 * gap) == after)
        }
    }

    static func flatten(_ segments: [ActivityTrack.Segment]) -> [ActivityTrack.Point] {
        var points: [ActivityTrack.Point] = []
        for segment in segments {
            for point in segment.points where points.last != point {
                points.append(point)
            }
        }
        return points
    }

    static func checkSegments(
        _ segments: [ActivityTrack.Segment], of track: ActivityTrack,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            Self.flatten(segments) == track.route, "cover the route", sourceLocation: sourceLocation
        )
        #expect(Set(segments.map(\.id)).count == segments.count, sourceLocation: sourceLocation)
        #expect(segments.allSatisfy { !$0.points.isEmpty }, sourceLocation: sourceLocation)
        for (before, after) in zip(segments, segments.dropFirst()) {
            #expect(
                before.points.last == after.points.first, "joined", sourceLocation: sourceLocation)
            #expect(
                before.zone != after.zone, "one stretch per zone", sourceLocation: sourceLocation)
        }
        for segment in segments {
            #expect(
                segment.zone.map { (0...4).contains($0) } ?? true, sourceLocation: sourceLocation)
        }
    }

    @Test("Segments are contiguous, cover the route and follow the zones", arguments: 0..<10)
    func segments(seed: Int) throws {
        var random = RecordingRandom(seed: UInt64(seed) + 9000)
        var pattern: [Int?] = []
        while pattern.count < 1200 {
            let rate: Int? = random.chance(0.1) ? nil : Self.rates[random.int(0...4)]
            pattern += [Int?](repeating: rate, count: random.int(20...80))
        }
        let run = RecordingRun.withHeartRate(seconds: 1200) { pattern[$0] }
        let track = run.track()
        let segments = track.segments(zones: try RecordingFixtures.zones())
        Self.checkSegments(segments, of: track)
        for segment in segments where segment.points.count > 2 {
            for point in segment.points.dropFirst().dropLast() {
                #expect(point.heartRate.map(RecordingFixtures.zone(of:)) == segment.zone)
            }
        }
    }

    @Test("Heart rate in three zones makes three stretches")
    func threeZones() throws {
        let run = RecordingRun.withHeartRate { $0 < 200 ? 110 : $0 < 400 ? 150 : 182 }
        let track = run.track()
        let segments = track.segments(zones: try RecordingFixtures.zones())
        Self.checkSegments(segments, of: track)
        #expect(segments.map(\.zone) == [0, 2, 4])
    }

    @Test("Every zone from 1 to 5", arguments: 0..<5)
    func eachZone(zone: Int) throws {
        let rate = Self.rates[zone]
        let track = RecordingRun.withHeartRate { _ in rate }.track()
        let segments = track.segments(zones: try RecordingFixtures.zones())
        #expect(segments.map(\.zone) == [zone])
        #expect(segments.first?.points == track.route)
    }

    @Test("Without zones the route is one stretch without a zone")
    func withoutZones() {
        let track = RecordingRun.withHeartRate { $0 < 300 ? 110 : 182 }.track()
        let segments = track.segments(zones: nil)
        #expect(segments.count == 1)
        #expect(segments.first?.zone == nil)
        #expect(segments.first?.points == track.route)
    }

    @Test("Without heart rate the route is one stretch without a zone")
    func withoutHeartRate() throws {
        let track = RecordingRun.withHeartRate { _ in nil }.track()
        let segments = track.segments(zones: try RecordingFixtures.zones())
        #expect(segments.count == 1)
        #expect(segments.first?.zone == nil)
        #expect(segments.first?.points == track.route)
    }
}
