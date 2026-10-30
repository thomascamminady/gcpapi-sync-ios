import Foundation
import GCPAPISync

extension SummarizedActivity {
    /// The demo activity with `id`, as the demo's activity ids encode kind and date.
    nonisolated static func sample(id: Int) -> Self? {
        let date = GarminDate.sampleOrigin.adding(days: id % 1_000_000_000)
        return switch id / 1_000_000_000 {
        case 20: sampleRun(on: date)
        case 21: sampleStrength(on: date)
        case 22: sampleRide(on: date)
        default: nil
        }
    }
}

extension GarminDate {
    /// The day the demo's seeds count from.
    nonisolated static let sampleOrigin =
        (try? GarminDate(year: 2000, month: 1, day: 1)) ?? .today()
}

extension FITActivity {
    /// A synthetic recording of a demo activity, one record every five seconds: a loop with
    /// hills for runs and rides, intervals on hard days, and sets for strength training.
    nonisolated static func sample(of activity: SummarizedActivity) -> Self {
        guard let local = activity.startTimeLocal, let duration = activity.duration else {
            return Self()
        }
        let start = local.date.startOfDay(in: .current)
            .addingTimeInterval(Double(local.time.hour * 3600 + local.time.minute * 60))
        switch Sport(typeKey: activity.activityType?.typeKey) {
        case .strength:
            return strength(start: start, duration: duration)
        case .cycling:
            return endurance(
                start: start, duration: duration,
                profile: Profile(
                    speed: activity.averageSpeed ?? 7, heartRate: activity.averageHR ?? 135,
                    loop: 12_000, hills: 40, lapLength: 5000, intervals: false,
                    power: activity.avgPower))
        default:
            return endurance(
                start: start, duration: duration,
                profile: Profile(
                    speed: activity.averageSpeed ?? 3, heartRate: activity.averageHR ?? 150,
                    loop: 3000, hills: 12, lapLength: 1000,
                    intervals: activity.activityName == "Intervals", power: nil))
        }
    }

    /// How a synthetic run or ride goes.
    nonisolated private struct Profile {
        /// Average metres per second and heart rate.
        let speed: Double
        let heartRate: Double
        /// Metres around the loop, and the height of its hills.
        let loop: Double
        let hills: Double
        let lapLength: Double
        let intervals: Bool
        /// Average watts, for rides.
        let power: Double?
    }

    nonisolated private static func endurance(
        start: Date, duration: Double, profile: Profile
    ) -> Self {
        let average = profile.speed
        let target = profile.heartRate
        let loop = profile.loop
        let intervals = profile.intervals
        let power = profile.power
        let center = (latitude: 47.3605, longitude: 8.5480)
        var records: [Record] = []
        var distance = 0.0
        var heartRate = 95.0
        for second in stride(from: 0.0, through: duration, by: 5) {
            // Ten minutes of warm-up, then three hard minutes and two easy ones on hard days.
            let effort =
                intervals && second > 600 && second < duration - 600
                ? (second.truncatingRemainder(dividingBy: 300) < 180 ? 1.18 : 0.8)
                : 0.97 + 0.04 * sin(second / 300 * 2 * .pi)
            let speed = average * effort
            distance += speed * 5
            // The heart follows the effort with a lag of about a minute.
            heartRate += (target * pow(effort, 0.7) - heartRate) * (1 - exp(-5 / 60.0))
            let angle = distance / loop * 2 * .pi
            let radius = loop / (2 * .pi)
            records.append(
                Record(
                    time: start.addingTimeInterval(second),
                    latitude: center.latitude + radius * 0.6 * sin(angle) / 111_320,
                    longitude: center.longitude + radius * 1.3 * cos(angle)
                        / (111_320 * cos(center.latitude * .pi / 180)),
                    altitude: 410 + profile.hills * sin(distance / 1500 * 2 * .pi),
                    heartRate: Int(heartRate.rounded()),
                    cadence: power == nil ? 86 + effort * 2 : 86,
                    distance: distance,
                    speed: speed,
                    power: power.map {
                        Int(($0 * effort + 25 * cos(distance / 1500 * 2 * .pi)).rounded())
                    }))
        }
        return Self(records: records, laps: laps(of: records, length: profile.lapLength))
    }

    /// Automatic laps of `length` metres.
    nonisolated private static func laps(of records: [Record], length: Double) -> [Lap] {
        let groups = Dictionary(grouping: records) { Int(($0.distance ?? 0) / length) }
        return groups.keys.sorted().compactMap { index in
            guard let group = groups[index], let first = group.first, let last = group.last else {
                return nil
            }
            let elapsed = last.time.timeIntervalSince(first.time) + 5
            let distance = (last.distance ?? 0) - (first.distance ?? 0) + (first.speed ?? 0) * 5
            let heartRates = group.compactMap(\.heartRate)
            return Lap(
                start: first.time, elapsed: elapsed, moving: elapsed, distance: distance,
                averageSpeed: distance / elapsed,
                averageHeartRate: heartRates.reduce(0, +) / max(1, heartRates.count),
                maxHeartRate: heartRates.max(), ascent: nil, averagePower: nil)
        }
    }

    /// Four exercises of three sets, a minute and a half of rest between sets.
    nonisolated private static func strength(start: Date, duration: Double) -> Self {
        let exercises: [(category: Int, reps: Int, weight: Double)] = [
            (28, 8, 80), (0, 8, 60), (23, 10, 50), (8, 6, 100),
        ]
        var sets: [ExerciseSet] = []
        var time = 300.0
        for exercise in exercises {
            for _ in 0..<3 {
                sets.append(
                    ExerciseSet(
                        start: start.addingTimeInterval(time), duration: 45,
                        repetitions: exercise.reps, weight: exercise.weight, isActive: true,
                        category: exercise.category))
                sets.append(
                    ExerciseSet(
                        start: start.addingTimeInterval(time + 45), duration: 90,
                        isActive: false))
                time += 135
            }
        }
        var heartRate = 90.0
        let records = stride(from: 0.0, through: duration, by: 5).map { second in
            let active = sets.contains { set in
                guard set.isActive, let begin = set.start?.timeIntervalSince(start) else {
                    return false
                }
                return second >= begin && second < begin + (set.duration ?? 0)
            }
            heartRate += ((active ? 138 : 98) - heartRate) * (1 - exp(-5 / 30.0))
            return Record(
                time: start.addingTimeInterval(second), heartRate: Int(heartRate.rounded()))
        }
        return Self(records: records, sets: sets)
    }
}
