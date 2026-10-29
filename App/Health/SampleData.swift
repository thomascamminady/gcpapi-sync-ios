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

extension GarminDate {
    /// A stable number per date that drives smooth day-to-day variation in the samples.
    nonisolated var sampleSeed: Int {
        (try? GarminDate(year: 2000, month: 1, day: 1).days(to: self)) ?? 0
    }

    /// `base` plus a sine wave of `period` days.
    nonisolated func sampleWave(_ period: Double, _ amplitude: Double, _ base: Double) -> Double {
        base + amplitude * sin(Double(sampleSeed) * 2 * .pi / period)
    }
}

extension DayHealth {
    /// Deterministic synthetic values for `date`.
    nonisolated static func sample(for date: GarminDate) -> Self {
        // A slow cycle of about five weeks, like a training block, under the daily noise.
        let form = sin(Double(date.sampleSeed) * 2 * .pi / 37)
        func wave(
            _ period: Double, _ amplitude: Double, _ base: Double, form weight: Double = 0
        )
            -> Int
        {
            Int((date.sampleWave(period, amplitude, base) + weight * form).rounded())
        }
        let sleep = wave(5.3, 1800, 26_400)
        // The runs the demo serves, oldest first, so this matches what the app computes.
        let estimates = (0..<VO2maxEstimator.window).reversed().compactMap { back in
            SummarizedActivity.sampleRun(on: date.adding(days: -back)).flatMap {
                VO2maxEstimator.estimate($0, maxHeartRate: Double(HeartRateZones.sampleMaximum))
            }
        }
        return DayHealth(
            date: date,
            steps: wave(3.7, 3500, 9800),
            stepGoal: 10_000,
            restingHeartRate: wave(6.1, 3, 48, form: -3),
            hrv: wave(4.6, 9, 58, form: 8),
            hrvStatus: "BALANCED",
            sleep: SleepNight(
                total: sleep, deep: sleep / 5, light: sleep / 2, rem: sleep / 4,
                awake: sleep / 20, score: wave(5.3, 9, 80, form: 6)),
            stress: wave(3.4, 9, 30, form: -8),
            bodyBatteryLow: wave(4.3, 8, 22),
            bodyBatteryHigh: wave(5.7, 10, 85),
            activeCalories: wave(3.9, 250, 650),
            intensityMinutes: wave(2.9, 25, 35),
            vo2max: VO2maxEstimator.trend(estimates, on: date)
        )
    }
}

extension SummarizedActivity {
    /// A synthetic morning run on four days a week, slowly getting faster and slower again.
    nonisolated static func sampleRun(on date: GarminDate) -> Self? {
        let seed = date.sampleSeed
        guard [0, 2, 4, 5].contains(seed % 7), let seven = try? GarminTime(hour: 7) else {
            return nil
        }
        let duration = date.sampleWave(3.1, 900, 2700).rounded()
        let speed = date.sampleWave(41, 0.15, 3.3)
        return SummarizedActivity(
            activityId: 20_000_000_000 + seed,
            activityName: "Morning Run",
            startTimeLocal: LocalDateTime(date: date, time: seven),
            activityType: ActivityType(typeKey: "running"),
            distance: (speed * duration).rounded(),
            duration: duration,
            averageSpeed: speed,
            averageHR: date.sampleWave(2.3, 6, 152).rounded(),
            avgGradeAdjustedSpeed: speed
        )
    }
}

extension HeartRateZones {
    /// The maximum heart rate of the synthetic athlete.
    nonisolated static let sampleMaximum = 190

    /// Synthetic running zones.
    nonisolated static let sample = Self(
        trainingMethod: "HR_MAX", restingHeartRateUsed: 48, maxHeartRateUsed: sampleMaximum,
        sport: "RUNNING")
}
