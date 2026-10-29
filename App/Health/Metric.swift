import Foundation
import SwiftUI

/// The metrics the dashboard shows, with everything needed to present them.
enum Metric: String, CaseIterable, Identifiable, Hashable {
    case steps
    case sleep
    case restingHeartRate
    case hrv
    case bodyBattery
    case stress
    case intensityMinutes

    var id: Self { self }

    var title: String {
        switch self {
        case .steps: String(localized: "Steps")
        case .sleep: String(localized: "Sleep")
        case .restingHeartRate: String(localized: "Resting Heart Rate")
        case .hrv: String(localized: "Heart Rate Variability")
        case .bodyBattery: String(localized: "Body Battery")
        case .stress: String(localized: "Stress")
        case .intensityMinutes: String(localized: "Intensity Minutes")
        }
    }

    var symbol: String {
        switch self {
        case .steps: "figure.walk"
        case .sleep: "bed.double.fill"
        case .restingHeartRate: "heart.fill"
        case .hrv: "waveform.path.ecg"
        case .bodyBattery: "bolt.heart.fill"
        case .stress: "brain.head.profile"
        case .intensityMinutes: "flame.fill"
        }
    }

    var tint: Color {
        switch self {
        case .steps: .teal
        case .sleep: .indigo
        case .restingHeartRate: .red
        case .hrv: .purple
        case .bodyBattery: .green
        case .stress, .intensityMinutes: .orange
        }
    }

    /// What the metric means, for the detail screen.
    var explanation: String {
        switch self {
        case .steps:
            String(
                localized: """
                    Steps counted by your watch. Garmin's daily goal adapts to your recent \
                    activity unless you set a fixed one.
                    """)
        case .sleep:
            String(
                localized: """
                    Time asleep each night, split into deep, light and REM sleep and time \
                    awake. The sleep score (0–100) combines duration, quality and recovery.
                    """)
        case .restingHeartRate:
            String(
                localized: """
                    Your lowest heart rate of the day at rest. It tends to fall as fitness \
                    improves; a sudden rise can come with stress, illness or fatigue.
                    """)
        case .hrv:
            String(
                localized: """
                    The overnight average of the variation between heartbeats. Garmin compares \
                    it with your personal baseline; Balanced means you are in your usual range.
                    """)
        case .bodyBattery:
            String(
                localized: """
                    Garmin's estimate of your energy reserves (0–100), charged by rest and \
                    sleep and drained by activity and stress. Bars span each day's lowest to \
                    highest level.
                    """)
        case .stress:
            String(
                localized: """
                    Average stress level (0–100), estimated from your heart while you are not \
                    active: 0–25 is rest, 26–50 low, 51–75 medium and 76–100 high.
                    """)
        case .intensityMinutes:
            String(
                localized: """
                    Minutes of moderate activity plus twice the vigorous ones. The WHO \
                    recommends at least 150 per week.
                    """)
        }
    }

    /// A headline value with its unit and a line of context.
    struct Summary: Equatable {
        let value: String
        let unit: String?
        let detail: String
    }

    /// The headline for a run of days.
    func summary(of history: HealthHistory) -> Summary {
        let count = history.days.count
        switch self {
        case .steps:
            let atGoal = history.days.filter { day in
                guard let steps = day.steps, let goal = day.stepGoal else { return false }
                return steps >= goal
            }.count
            return Summary(
                value: Format.number(history.average(\.steps)), unit: String(localized: "per day"),
                detail: String(localized: "\(atGoal) of \(count) days at goal"))
        case .sleep:
            let average = history.averageSleep
            return Summary(
                value: Format.duration(seconds: average?.total), unit: String(localized: "average"),
                detail: average?.score.map { String(localized: "Average sleep score \($0)") }
                    ?? String(localized: "No sleep score"))
        case .restingHeartRate:
            let average = Format.number(history.average(\.restingHeartRate))
            return Summary(
                value: Format.number(history.latest(\.restingHeartRate)), unit: "bpm",
                detail: String(localized: "\(count)-day average \(average) bpm"))
        case .hrv:
            let average = Format.number(history.average(\.hrv))
            return Summary(
                value: Format.number(history.latest(\.hrv)), unit: "ms",
                detail: String(localized: "Last night · \(count)-day average \(average) ms"))
        case .bodyBattery:
            let low = Format.number(history.average(\.bodyBatteryLow))
            let high = Format.number(history.average(\.bodyBatteryHigh))
            return Summary(
                value: Format.number(history.latest(\.bodyBatteryHigh)),
                unit: String(localized: "latest high"),
                detail: String(localized: "Average range \(low)–\(high)"))
        case .stress:
            let average = history.average(\.stress)
            return Summary(
                value: Format.number(average), unit: String(localized: "average"),
                detail: Format.stressLabel(average))
        case .intensityMinutes:
            let perWeek = count == 0 ? 0 : history.total(\.intensityMinutes) * 7 / count
            return Summary(
                value: perWeek.formatted(), unit: String(localized: "per week"),
                detail: perWeek >= 150
                    ? String(localized: "Above the WHO goal of 150")
                    : String(localized: "\(150 - perWeek) per week below the WHO goal of 150"))
        }
    }

    /// The headline for one day.
    func summary(of day: DayHealth) -> Summary {
        Summary(value: value(of: day), unit: unit, detail: detail(of: day) ?? "")
    }

    /// The unit a day's value is shown in.
    var unit: String? {
        switch self {
        case .steps: String(localized: "steps")
        case .sleep: nil
        case .restingHeartRate: "bpm"
        case .hrv: "ms"
        case .bodyBattery: String(localized: "high")
        case .stress: String(localized: "average")
        case .intensityMinutes: String(localized: "minutes")
        }
    }

    /// A day's value, or an en dash without data.
    func value(of day: DayHealth) -> String {
        switch self {
        case .steps: Format.number(day.steps)
        case .sleep: Format.duration(seconds: day.sleep?.total)
        case .restingHeartRate: Format.number(day.restingHeartRate)
        case .hrv: Format.number(day.hrv)
        case .bodyBattery: Format.number(day.bodyBatteryHigh)
        case .stress: Format.number(day.stress)
        case .intensityMinutes: Format.number(day.intensityMinutes)
        }
    }

    /// Context for a day's value, if there is any.
    func detail(of day: DayHealth) -> String? {
        switch self {
        case .steps:
            day.stepGoal.map { String(localized: "Goal \($0.formatted())") }
        case .sleep:
            day.sleep.map { night in
                [
                    night.score.map { String(localized: "Score \($0)") },
                    String(localized: "Deep \(Format.duration(seconds: night.deep))"),
                    String(localized: "REM \(Format.duration(seconds: night.rem))"),
                ].compactMap(\.self).joined(separator: " · ")
            }
        case .hrv:
            Format.hrvStatus(day.hrvStatus)?.label
        case .bodyBattery:
            day.bodyBatteryLow.map { String(localized: "Lowest \($0)") }
        case .stress:
            day.stress.map { Format.stressLabel($0) }
        case .restingHeartRate, .intensityMinutes:
            nil
        }
    }

    /// Whether `day` has a value for this metric.
    func hasValue(_ day: DayHealth) -> Bool {
        value(of: day) != "–"
    }
}
