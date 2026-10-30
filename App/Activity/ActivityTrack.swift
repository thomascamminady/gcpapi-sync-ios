import Foundation

/// A recorded activity prepared for the activity screen: samples to chart, the route to
/// map, splits, laps and strength sets.
nonisolated struct ActivityTrack: Hashable, Sendable {
    /// The average of the records in a slice of time.
    struct Sample: Identifiable, Hashable, Sendable {
        /// Seconds of timer time since the start, without pauses.
        let elapsed: Double
        /// Metres from the start.
        let distance: Double?
        let heartRate: Double?
        /// Metres per second.
        let speed: Double?
        let altitude: Double?
        /// Steps per minute on foot, revolutions per minute on a bike.
        let cadence: Double?
        let power: Double?

        var id: Double { elapsed }
    }

    /// A point of the route.
    struct Point: Hashable, Sendable {
        let latitude: Double
        let longitude: Double
        let elapsed: Double
        let heartRate: Int?

        var geoPoint: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
    }

    /// A stretch of the route in one heart rate zone (0 to 4), or without heart rate.
    struct Segment: Identifiable, Hashable, Sendable {
        let id: Int
        let zone: Int?
        let points: [Point]
    }

    /// One kilometre or mile.
    struct Split: Identifiable, Hashable, Sendable {
        let number: Int
        /// Metres; the last split is usually shorter.
        let distance: Double
        /// Seconds.
        let duration: Double
        let heartRate: Double?
        /// Metres climbed.
        let ascent: Double

        var id: Int { number }
        /// Metres per second.
        var speed: Double { duration > 0 ? distance / duration : 0 }
    }

    /// The most samples charts get; more add nothing visible but cost time when scrubbing.
    static let maxSamples = 500
    /// The most route points the map gets.
    static let maxPoints = 1500

    let samples: [Sample]
    let route: [Point]
    let splits: [Split]
    let laps: [FITActivity.Lap]
    let sets: [FITActivity.ExerciseSet]
    /// Seconds of timer time from the first record to the last.
    let duration: Double

    /// Whether the watch's laps are the same as the splits, as with automatic laps of a
    /// kilometre or mile, so that showing both would repeat them.
    var lapsRepeatSplits: Bool {
        laps.count == splits.count
            && zip(laps, splits).allSatisfy { lap, split in
                guard let distance = lap.distance, let time = lap.moving ?? lap.elapsed else {
                    return false
                }
                return abs(distance - split.distance) <= max(15, split.distance * 0.02)
                    && abs(time - split.duration) <= 5
            }
    }

    func has(_ value: KeyPath<Sample, Double?>) -> Bool {
        samples.contains { $0[keyPath: value] != nil }
    }

    /// `fit`'s records; `splitLength` is a kilometre or a mile in metres.
    init(_ fit: FITActivity, sport: Sport, splitLength: Double) {
        let records = fit.records.sorted { $0.time < $1.time }
        let start = records.first?.time ?? .distantPast
        let clock = TimerClock(start: start, events: fit.timerEvents)
        duration = records.last.map { clock.seconds(at: $0.time) } ?? 0
        // FIT counts running cadence in strides per minute; people count steps.
        let cadenceFactor: Double = [.running, .walking].contains(sport) ? 2 : 1
        samples = Self.samples(
            records, clock: clock, duration: duration, cadenceFactor: cadenceFactor)
        let located = records.compactMap { record -> Point? in
            guard let latitude = record.latitude, let longitude = record.longitude,
                latitude != 0 || longitude != 0
            else { return nil }
            return Point(
                latitude: latitude, longitude: longitude,
                elapsed: clock.seconds(at: record.time), heartRate: record.heartRate)
        }
        let stride = max(1, Int((Double(located.count) / Double(Self.maxPoints)).rounded(.up)))
        var route = located.enumerated().filter { $0.offset.isMultiple(of: stride) }.map(\.element)
        if let last = located.last, route.last != last {
            route.append(last)
        }
        self.route = route
        splits = Self.splits(records, clock: clock, length: splitLength)
        laps = fit.laps
        sets = fit.sets
    }

    /// The records averaged over equal slices of time.
    private static func samples(
        _ records: [FITActivity.Record], clock: TimerClock, duration: Double, cadenceFactor: Double
    ) -> [Sample] {
        guard !records.isEmpty else { return [] }
        let count = min(records.count, maxSamples)
        let width = max(1, duration / Double(count))
        let buckets = Dictionary(grouping: records) { record in
            min(count - 1, Int(clock.seconds(at: record.time) / width))
        }
        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }
        return buckets.keys.sorted().compactMap { index in
            guard let bucket = buckets[index] else { return nil }
            return Sample(
                elapsed: (Double(index) + 0.5) * width,
                distance: bucket.compactMap(\.distance).max(),
                heartRate: mean(bucket.compactMap { $0.heartRate.map(Double.init) }),
                speed: mean(bucket.compactMap(\.speed)),
                altitude: mean(bucket.compactMap(\.altitude)),
                cadence: mean(bucket.compactMap(\.cadence).filter { $0 > 0 }).map {
                    $0 * cadenceFactor
                },
                power: mean(bucket.compactMap { $0.power.map(Double.init) }))
        }
    }

    /// Splits of `length` metres, timed where the distance crosses each boundary.
    private static func splits(
        _ records: [FITActivity.Record], clock: TimerClock, length: Double
    )
        -> [Split]
    {
        var splits: [Split] = []
        var splitStart: (time: Double, distance: Double) = (0, 0)
        var heartRates: [Int] = []
        var ascent = 0.0
        var reference: Double?
        var previous: (time: Double, distance: Double)?
        for record in records {
            guard let distance = record.distance else { continue }
            let time = clock.seconds(at: record.time)
            if let heartRate = record.heartRate {
                heartRates.append(heartRate)
            }
            // Climbing counts only past a metre, so that sensor noise adds nothing.
            if let altitude = record.altitude {
                if let base = reference {
                    if altitude - base > 1 {
                        ascent += altitude - base
                        reference = altitude
                    } else if base - altitude > 1 {
                        reference = altitude
                    }
                } else {
                    reference = altitude
                }
            }
            let boundary = Double(splits.count + 1) * length
            if distance >= boundary, let previous {
                let share =
                    distance > previous.distance
                    ? (boundary - previous.distance) / (distance - previous.distance) : 1
                let crossing = previous.time + share * (time - previous.time)
                splits.append(
                    Split(
                        number: splits.count + 1, distance: length,
                        duration: crossing - splitStart.time,
                        heartRate: heartRates.isEmpty
                            ? nil : Double(heartRates.reduce(0, +)) / Double(heartRates.count),
                        ascent: ascent))
                splitStart = (crossing, boundary)
                heartRates = []
                ascent = 0
            }
            previous = (time, distance)
        }
        // A last, shorter split, unless it is only a few steps.
        if let previous, previous.distance - splitStart.distance > length * 0.1 {
            splits.append(
                Split(
                    number: splits.count + 1, distance: previous.distance - splitStart.distance,
                    duration: previous.time - splitStart.time,
                    heartRate: heartRates.isEmpty
                        ? nil : Double(heartRates.reduce(0, +)) / Double(heartRates.count),
                    ascent: ascent))
        }
        return splits
    }

    /// The route in stretches of one heart rate zone each, joined end to start.
    func segments(zones: HeartRateZoneSet?) -> [Segment] {
        func zone(_ point: Point) -> Int? {
            guard let zones, let heartRate = point.heartRate else { return nil }
            return zones.floors.lastIndex { heartRate >= $0 }
        }
        var segments: [Segment] = []
        var current: [Point] = []
        var currentZone: Int?
        for point in route {
            let pointZone = zone(point)
            if current.isEmpty {
                currentZone = pointZone
            } else if pointZone != currentZone {
                current.append(point)
                segments.append(Segment(id: segments.count, zone: currentZone, points: current))
                current = []
                currentZone = pointZone
            }
            current.append(point)
        }
        if current.count > 1 || (segments.isEmpty && !current.isEmpty) {
            segments.append(Segment(id: segments.count, zone: currentZone, points: current))
        }
        return segments
    }

    /// The sample nearest to `elapsed` seconds.
    func sample(near elapsed: Double) -> Sample? {
        samples.min { abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed) }
    }

    /// The route point nearest to `elapsed` seconds.
    func point(near elapsed: Double) -> Point? {
        route.min { abs($0.elapsed - elapsed) < abs($1.elapsed - elapsed) }
    }
}

/// Timer time: seconds since the start without the pauses between a timer stop and the next
/// start.
nonisolated struct TimerClock {
    let start: Date
    /// Pauses in seconds since the start.
    let pauses: [ClosedRange<Double>]

    init(start: Date, events: [FITActivity.TimerEvent]) {
        self.start = start
        var pauses: [ClosedRange<Double>] = []
        var stopped: Double?
        for event in events.sorted(by: { $0.time < $1.time }) {
            let seconds = event.time.timeIntervalSince(start)
            if event.isStart, let since = stopped {
                pauses.append(since...max(since, seconds))
                stopped = nil
            } else if !event.isStart, stopped == nil {
                stopped = seconds
            }
        }
        self.pauses = pauses
    }

    /// The timer time at `date`; inside a pause, the time the pause began.
    func seconds(at date: Date) -> Double {
        let seconds = date.timeIntervalSince(start)
        return seconds
            - pauses.reduce(0) { paused, pause in
                paused + max(0, min(seconds, pause.upperBound) - pause.lowerBound)
            }
    }
}

/// Garmin's exercise categories of strength sets, from the FIT profile.
nonisolated enum ExerciseCategory {
    static func name(_ category: Int?) -> String? {
        guard let category, category < names.count else { return nil }
        return names[category]
    }

    private static let names = [
        String(localized: "Bench Press"), String(localized: "Calf Raise"),
        String(localized: "Cardio"), String(localized: "Carry"), String(localized: "Chop"),
        String(localized: "Core"), String(localized: "Crunch"), String(localized: "Curl"),
        String(localized: "Deadlift"), String(localized: "Flye"), String(localized: "Hip Raise"),
        String(localized: "Hip Stability"), String(localized: "Hip Swing"),
        String(localized: "Hyperextension"), String(localized: "Lateral Raise"),
        String(localized: "Leg Curl"), String(localized: "Leg Raise"), String(localized: "Lunge"),
        String(localized: "Olympic Lift"), String(localized: "Plank"), String(localized: "Plyo"),
        String(localized: "Pull-Up"), String(localized: "Push-Up"), String(localized: "Row"),
        String(localized: "Shoulder Press"), String(localized: "Shoulder Stability"),
        String(localized: "Shrug"), String(localized: "Sit-Up"), String(localized: "Squat"),
        String(localized: "Total Body"), String(localized: "Triceps Extension"),
        String(localized: "Warm-Up"), String(localized: "Run"),
    ]
}
