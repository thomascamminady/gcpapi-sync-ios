import Foundation
import GCPAPISync

extension HealthHistory {
    /// A plausible, synthetic week for previews, loading placeholders and the demo mode.
    nonisolated static func sample(endingOn end: GarminDate, days: Int = 7) -> Self {
        Self(
            days: (0..<days).map { offset in
                DayHealth.sample(for: end.adding(days: offset + 1 - days))
            })
    }
}

extension DayHealth {
    /// Deterministic synthetic values for `date`.
    nonisolated static func sample(for date: GarminDate) -> Self {
        // A stable number per date drives smooth day-to-day variation.
        let seed = Double((try? GarminDate(year: 2000, month: 1, day: 1).days(to: date)) ?? 0)
        func wave(_ period: Double, _ amplitude: Double, _ base: Double) -> Int {
            Int((base + amplitude * sin(seed * 2 * .pi / period)).rounded())
        }
        let sleep = wave(5.3, 1800, 26_400)
        return DayHealth(
            date: date,
            steps: wave(3.7, 3500, 9800),
            stepGoal: 10_000,
            restingHeartRate: wave(6.1, 3, 48),
            hrv: wave(4.6, 9, 58),
            hrvStatus: "BALANCED",
            sleep: SleepNight(
                total: sleep, deep: sleep / 5, light: sleep / 2, rem: sleep / 4,
                awake: sleep / 20, score: wave(5.3, 9, 80)),
            stress: wave(3.4, 9, 30),
            bodyBatteryLow: wave(4.3, 8, 22),
            bodyBatteryHigh: wave(5.7, 10, 85),
            activeCalories: wave(3.9, 250, 650),
            intensityMinutes: wave(2.9, 25, 35)
        )
    }
}
