import Foundation
import GCPAPISync

/// One activity, with what the training screens show.
nonisolated struct Workout: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let typeKey: String
    let sport: Sport
    /// The local calendar day it started on.
    let date: GarminDate
    let start: Date?
    /// Seconds.
    let duration: Double
    /// Metres.
    let distance: Double?
    /// Metres per second.
    let averageSpeed: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    /// Metres.
    let elevationGain: Double?
    let calories: Double?
    /// Watts.
    let averagePower: Double?
    let normalizedPower: Double?
    /// Steps per minute when running, revolutions per minute when cycling.
    let cadence: Double?
    /// Garmin's training load: the EPOC the activity caused.
    let trainingLoad: Double?
    /// Garmin's aerobic and anaerobic training effect, 0 to 5.
    let aerobicEffect: Double?
    let anaerobicEffect: Double?
    /// Garmin's primary benefit, such as `AEROBIC_BASE`.
    let primaryBenefit: String?
    let aerobicMessage: String?
    let anaerobicMessage: String?
    /// Seconds in heart rate zones 1 to 5; empty when unknown.
    let heartRateZones: [Double]
    /// Seconds in power zones 1 to 7; empty when unknown.
    let powerZones: [Double]
    let location: String?

    /// The workout of a Garmin activity with a start date and a duration.
    init?(_ activity: SummarizedActivity) {
        guard let date = activity.startTimeLocal?.date, let duration = activity.duration else {
            return nil
        }
        let typeKey = activity.activityType?.typeKey ?? "other"
        id = activity.activityId
        self.typeKey = typeKey
        sport = Sport(typeKey: typeKey)
        name = activity.activityName.flatMap { $0.isEmpty ? nil : $0 } ?? sport.title
        self.date = date
        start = activity.startTimeGMT ?? activity.startTimeLocal.map(Self.date)
        self.duration = duration
        distance = activity.distance.flatMap { $0 > 0 ? $0 : nil }
        averageSpeed = activity.averageSpeed.flatMap { $0 > 0 ? $0 : nil }
        averageHeartRate = activity.averageHR
        maxHeartRate = activity.maxHR
        elevationGain = activity.elevationGain
        calories = activity.calories
        averagePower = activity.avgPower
        normalizedPower = activity.normPower
        cadence =
            activity.averageRunningCadenceInStepsPerMinute
            ?? activity.averageBikingCadenceInRevPerMinute
        trainingLoad = activity.activityTrainingLoad
        aerobicEffect = activity.aerobicTrainingEffect
        anaerobicEffect = activity.anaerobicTrainingEffect
        primaryBenefit = activity.trainingEffectLabel
        aerobicMessage = activity.aerobicTrainingEffectMessage
        anaerobicMessage = activity.anaerobicTrainingEffectMessage
        heartRateZones = Self.zones([
            activity.hrTimeInZone1, activity.hrTimeInZone2, activity.hrTimeInZone3,
            activity.hrTimeInZone4, activity.hrTimeInZone5,
        ])
        powerZones = Self.zones([
            activity.powerTimeInZone1, activity.powerTimeInZone2, activity.powerTimeInZone3,
            activity.powerTimeInZone4, activity.powerTimeInZone5, activity.powerTimeInZone6,
            activity.powerTimeInZone7,
        ])
        location = activity.locationName
    }

    /// The moment of a local date and time in the current time zone.
    private static func date(_ local: LocalDateTime) -> Date {
        let time = local.time
        return local.date.startOfDay(in: .current)
            .addingTimeInterval(Double(time.hour * 3600 + time.minute * 60 + time.second))
    }

    /// The seconds per zone, or none when Garmin reported no time in any zone.
    private static func zones(_ seconds: [Double?]) -> [Double] {
        let values = seconds.map { $0 ?? 0 }
        return values.contains { $0 > 0 } ? values : []
    }
}
