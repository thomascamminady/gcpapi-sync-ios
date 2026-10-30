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
        Self.sampleOrigin.days(to: self)
    }

    /// Whether the synthetic athlete trains hard on this day: intervals or a long ride.
    nonisolated var isHardSampleDay: Bool {
        sampleSeed % 7 == 4 || sampleSeed % 14 == 6
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
        // Hard training lowers HRV and sleep and raises resting heart rate and stress the next
        // day, and a little the day after.
        let strain =
            (date.adding(days: -1).isHardSampleDay ? 1 : 0)
            + (date.adding(days: -2).isHardSampleDay ? 0.4 : 0)
        func wave(
            _ period: Double, _ amplitude: Double, _ base: Double, form weight: Double = 0,
            strain effect: Double = 0
        ) -> Int {
            let value = date.sampleWave(period, amplitude, base) + weight * form + effect * strain
            return Int(value.rounded())
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
            restingHeartRate: wave(6.1, 3, 48, form: -3, strain: 3),
            hrv: wave(4.6, 9, 58, form: 8, strain: -9),
            hrvStatus: "BALANCED",
            sleep: SleepNight(
                total: sleep, deep: sleep / 5, light: sleep / 2, rem: sleep / 4,
                awake: sleep / 20, score: wave(5.3, 9, 80, form: 6, strain: -7)),
            stress: wave(3.4, 9, 30, form: -8, strain: 8),
            bodyBatteryLow: wave(4.3, 8, 22),
            bodyBatteryHigh: wave(5.7, 10, 85),
            activeCalories: wave(3.9, 250, 650),
            intensityMinutes: wave(2.9, 25, 35),
            vo2max: VO2maxEstimator.trend(estimates, on: date)
        )
    }
}

extension SummarizedActivity {
    /// The synthetic activities of `date`: runs on four days a week, strength training on two,
    /// and a long ride every other Sunday-like day.
    nonisolated static func sampleActivities(on date: GarminDate) -> [Self] {
        [sampleRun(on: date), sampleStrength(on: date), sampleRide(on: date)].compactMap(\.self)
    }

    /// A synthetic morning run on four days a week, slowly getting faster and slower again.
    nonisolated static func sampleRun(on date: GarminDate) -> Self? {
        let seed = date.sampleSeed
        guard [0, 2, 4, 5].contains(seed % 7), let seven = try? GarminTime(hour: 7) else {
            return nil
        }
        let duration = date.sampleWave(3.1, 900, 2700).rounded()
        let speed = date.sampleWave(41, 0.15, 3.3)
        let heartRate = date.sampleWave(2.3, 6, 152).rounded()
        let intensity = heartRate / Double(HeartRateZones.sampleMaximum)
        let hard = date.isHardSampleDay
        return SummarizedActivity(
            activityId: 20_000_000_000 + seed,
            activityName: hard ? "Intervals" : "Morning Run",
            startTimeLocal: LocalDateTime(date: date, time: seven),
            activityType: ActivityType(typeKey: "running"),
            distance: (speed * duration).rounded(),
            duration: duration,
            elevationGain: date.sampleWave(4.1, 40, 60).rounded(),
            averageSpeed: speed,
            startLatitude: SampleLoop.start.latitude,
            startLongitude: SampleLoop.start.longitude,
            calories: (duration / 60 * 12).rounded(),
            averageHR: heartRate,
            maxHR: heartRate + 18,
            averageRunningCadenceInStepsPerMinute: date.sampleWave(5.9, 3, 172).rounded(),
            aerobicTrainingEffect: hard
                ? 3.9 : (date.sampleWave(3.7, 0.5, 2.8) * 10).rounded() / 10,
            anaerobicTrainingEffect: hard ? 2.6 : 0.4,
            locationName: "Riverside",
            endLatitude: SampleLoop.start.latitude,
            endLongitude: SampleLoop.start.longitude,
            trainingEffectLabel: hard ? "VO2MAX" : "AEROBIC_BASE",
            activityTrainingLoad: (duration / 60 * (0.6 + 4 * max(0, intensity - 0.55))).rounded()
                + (hard ? 60 : 0),
            aerobicTrainingEffectMessage: hard
                ? "IMPROVING_VO2_MAX_15" : "MAINTAINING_AEROBIC_BASE_1",
            anaerobicTrainingEffectMessage: hard
                ? "MAINTAINING_ANAEROBIC_BASE_1" : "NO_ANAEROBIC_BENEFIT_0",
            avgGradeAdjustedSpeed: speed,
            hrTimeInZone1: (duration * 0.05).rounded(),
            hrTimeInZone2: (duration * (hard ? 0.2 : 0.3)).rounded(),
            hrTimeInZone3: (duration * (hard ? 0.3 : 0.45)).rounded(),
            hrTimeInZone4: (duration * (hard ? 0.3 : 0.18)).rounded(),
            hrTimeInZone5: (duration * (hard ? 0.15 : 0.02)).rounded()
        )
    }

    /// Strength training on two days a week.
    nonisolated static func sampleStrength(on date: GarminDate) -> Self? {
        let seed = date.sampleSeed
        guard [1, 3].contains(seed % 7), let evening = try? GarminTime(hour: 18, minute: 30) else {
            return nil
        }
        let duration = date.sampleWave(4.3, 300, 2700).rounded()
        return SummarizedActivity(
            activityId: 21_000_000_000 + seed,
            activityName: "Strength",
            startTimeLocal: LocalDateTime(date: date, time: evening),
            activityType: ActivityType(typeKey: "strength_training"),
            duration: duration,
            calories: (duration / 60 * 6).rounded(),
            averageHR: 108,
            maxHR: 141,
            aerobicTrainingEffect: 1.4,
            anaerobicTrainingEffect: 1.1,
            trainingEffectLabel: "UNKNOWN",
            activityTrainingLoad: (duration / 60 * 0.7).rounded(),
            aerobicTrainingEffectMessage: "MINOR_AEROBIC_BENEFIT_0",
            anaerobicTrainingEffectMessage: "MINOR_ANAEROBIC_BENEFIT_0",
            hrTimeInZone1: (duration * 0.6).rounded(),
            hrTimeInZone2: (duration * 0.35).rounded(),
            hrTimeInZone3: (duration * 0.05).rounded(),
            hrTimeInZone4: 0,
            hrTimeInZone5: 0
        )
    }

    /// A long ride every other week.
    nonisolated static func sampleRide(on date: GarminDate) -> Self? {
        let seed = date.sampleSeed
        guard seed % 14 == 6, let nine = try? GarminTime(hour: 9) else { return nil }
        let duration = date.sampleWave(5.3, 1800, 7200).rounded()
        let speed = 7.4
        return SummarizedActivity(
            activityId: 22_000_000_000 + seed,
            activityName: "Long Ride",
            startTimeLocal: LocalDateTime(date: date, time: nine),
            activityType: ActivityType(typeKey: "road_biking"),
            distance: (speed * duration).rounded(),
            duration: duration,
            elevationGain: 640,
            averageSpeed: speed,
            startLatitude: SampleLoop.start.latitude,
            startLongitude: SampleLoop.start.longitude,
            calories: (duration / 60 * 10).rounded(),
            averageHR: 134,
            maxHR: 168,
            averageBikingCadenceInRevPerMinute: 86,
            avgPower: 188,
            aerobicTrainingEffect: 3.3,
            anaerobicTrainingEffect: 0.6,
            normPower: 204,
            locationName: "Hill Country",
            endLatitude: SampleLoop.start.latitude,
            endLongitude: SampleLoop.start.longitude,
            trainingEffectLabel: "AEROBIC_BASE",
            activityTrainingLoad: (duration / 60 * 1.2).rounded(),
            aerobicTrainingEffectMessage: "IMPROVING_AEROBIC_ENDURANCE_10",
            anaerobicTrainingEffectMessage: "NO_ANAEROBIC_BENEFIT_0",
            hrTimeInZone1: (duration * 0.1).rounded(),
            hrTimeInZone2: (duration * 0.55).rounded(),
            hrTimeInZone3: (duration * 0.3).rounded(),
            hrTimeInZone4: (duration * 0.05).rounded(),
            hrTimeInZone5: 0,
            powerTimeInZone1: (duration * 0.15).rounded(),
            powerTimeInZone2: (duration * 0.45).rounded(),
            powerTimeInZone3: (duration * 0.3).rounded(),
            powerTimeInZone4: (duration * 0.08).rounded(),
            powerTimeInZone5: (duration * 0.02).rounded()
        )
    }
}

extension HeartRateZones {
    /// The maximum heart rate of the synthetic athlete.
    nonisolated static let sampleMaximum = 190

    /// Synthetic running zones.
    nonisolated static let sample = Self(
        trainingMethod: "HR_MAX", restingHeartRateUsed: 48, zone1Floor: 95, zone2Floor: 114,
        zone3Floor: 133, zone4Floor: 152, zone5Floor: 171, maxHeartRateUsed: sampleMaximum,
        sport: "RUNNING")
}

extension TrainingData {
    /// Synthetic training for previews, loading placeholders and the demo mode.
    nonisolated static func sample(endingOn end: GarminDate) -> Self {
        let first = end.adding(days: 1 - TrainingLoader.shownDays - TrainingLoader.warmUpDays)
        return TrainingLoader.assemble(
            activities: (0...first.days(to: end)).flatMap {
                SummarizedActivity.sampleActivities(on: first.adding(days: $0))
            },
            zones: [.sample], endingOn: end, calendar: .current)
    }
}
