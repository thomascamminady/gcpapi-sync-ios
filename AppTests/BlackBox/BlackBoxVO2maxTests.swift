import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// Daniels and Gilbert's oxygen cost of running at `speed` metres per minute.
nonisolated private func danielsGilbert(_ speed: Double) -> Double {
    -4.60 + 0.182258 * speed + 0.000104 * speed * speed
}

/// The effective VO2max of running at `speed` metres per minute at `share` of the maximum
/// heart rate (Swain et al.).
nonisolated private func effective(_ speed: Double, share: Double) -> Double {
    danielsGilbert(speed) / ((share - 0.37) / 0.64)
}

/// A steady 10 km run at 200 m/min with an average heart rate of `heartRate`.
private func run(
    on date: GarminDate = AnalyticsBlackBox.reference, typeKey: String = "running",
    duration: Double = 3000, distance: Double = 10_000, speed: Double? = 200.0 / 60,
    gradeAdjusted: Double? = 200.0 / 60, heartRate: Double? = 160
) -> SummarizedActivity {
    AnalyticsBlackBox.activity(
        id: 1, on: date, typeKey: typeKey, duration: duration, distance: distance, load: 120,
        speed: speed, gradeAdjusted: gradeAdjusted, heartRate: heartRate,
        maxHeartRate: heartRate.map { $0 + 8 })
}

@Suite("VO2max estimator")
struct BlackBoxVO2maxTests {
    @Test("Thirty days of runs, of Garmin's running types")
    func constants() {
        #expect(VO2maxEstimator.window == 30)
        #expect(
            VO2maxEstimator.runningTypes.isSuperset(of: [
                "running", "trail_running", "treadmill_running", "track_running",
            ]))
        #expect(!VO2maxEstimator.runningTypes.contains("cycling"))
        #expect(!VO2maxEstimator.runningTypes.contains("walking"))
    }

    @Test("Daniels and Gilbert's oxygen cost", arguments: [100.0, 150, 200, 268, 300, 400])
    func cost(speed: Double) {
        #expect(
            AnalyticsBlackBox.isClose(
                VO2maxEstimator.cost(metresPerMinute: speed), danielsGilbert(speed)))
    }

    @Test("Faster running costs more oxygen")
    func costIncreases() {
        let costs = stride(from: 60.0, through: 500, by: 10).map {
            VO2maxEstimator.cost(metresPerMinute: $0)
        }
        #expect(zip(costs, costs.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test(
        "A steady run's estimate: its cost over the share of VO2max its heart rate implies",
        arguments: [133.0, 150, 160, 175, 190])
    func estimate(heartRate: Double) throws {
        let estimate = try #require(
            VO2maxEstimator.estimate(run(heartRate: heartRate), maxHeartRate: 190))
        #expect(
            AnalyticsBlackBox.isClose(
                estimate.vo2max, effective(200, share: heartRate / 190), tolerance: 1e-6))
        #expect(estimate.date == AnalyticsBlackBox.reference)
        #expect(estimate.duration == 3000)
    }

    @Test("The grade-adjusted speed is the one that counts")
    func gradeAdjusted() throws {
        let hilly = run(speed: 2.8, gradeAdjusted: 200.0 / 60)
        let estimate = try #require(VO2maxEstimator.estimate(hilly, maxHeartRate: 190))
        #expect(
            AnalyticsBlackBox.isClose(
                estimate.vo2max, effective(200, share: 160.0 / 190), tolerance: 1e-6))
    }

    @Test("At least 15 minutes and 2.5 km")
    func minimumRun() {
        #expect(
            VO2maxEstimator.estimate(run(duration: 900, distance: 3000), maxHeartRate: 190) != nil)
        #expect(
            VO2maxEstimator.estimate(run(duration: 899, distance: 3000), maxHeartRate: 190) == nil)
        #expect(
            VO2maxEstimator.estimate(run(duration: 1200, distance: 2500), maxHeartRate: 190) != nil)
        #expect(
            VO2maxEstimator.estimate(run(duration: 1200, distance: 2499), maxHeartRate: 190) == nil)
    }

    @Test(
        "Only between 50 and 100 % of VO2max",
        arguments: [
            (0.60, false), (0.68, false), (0.70, true), (0.85, true), (1.0, true),
            (1.02, false), (1.2, false),
        ])
    func intensity(share: Double, accepted: Bool) {
        let estimate = VO2maxEstimator.estimate(run(heartRate: 190 * share), maxHeartRate: 190)
        #expect((estimate != nil) == accepted)
        if let estimate {
            #expect((25...90).contains(estimate.vo2max))
        }
    }

    @Test("Without a heart rate or a speed there is no estimate")
    func missingValues() {
        #expect(VO2maxEstimator.estimate(run(heartRate: nil), maxHeartRate: 190) == nil)
        #expect(
            VO2maxEstimator.estimate(run(speed: nil, gradeAdjusted: nil), maxHeartRate: 190) == nil)
        #expect(VO2maxEstimator.estimate(run(), maxHeartRate: 0) == nil)
    }

    @Test("Rides are not runs")
    func notRuns() {
        #expect(VO2maxEstimator.estimate(run(typeKey: "cycling"), maxHeartRate: 190) == nil)
        #expect(VO2maxEstimator.estimate(run(typeKey: "trail_running"), maxHeartRate: 190) != nil)
    }

    @Test("The trend is the duration-weighted mean of the window's estimates")
    func trend() throws {
        let day = AnalyticsBlackBox.reference
        let estimates = [
            VO2maxEstimator.Estimate(date: day, duration: 3600, vo2max: 50),
            VO2maxEstimator.Estimate(date: day.adding(days: -10), duration: 1800, vo2max: 40),
            VO2maxEstimator.Estimate(date: day.adding(days: -29), duration: 1800, vo2max: 46),
            VO2maxEstimator.Estimate(date: day.adding(days: -30), duration: 9000, vo2max: 20),
            VO2maxEstimator.Estimate(date: day.adding(days: 1), duration: 9000, vo2max: 90),
        ]
        let trend = try #require(VO2maxEstimator.trend(estimates, on: day))
        let weighted: Double = 50 * 3600 + 40 * 1800 + 46 * 1800
        #expect(AnalyticsBlackBox.isClose(trend, weighted / 7200))
        #expect(VO2maxEstimator.trend(estimates, on: day.adding(days: -31)) == nil)
        #expect(VO2maxEstimator.trend([], on: day) == nil)
    }

    @Test("The trend of random estimates stays between their extremes")
    func randomTrend() {
        var random = BlackBoxRandom(seed: 30)
        let first = GarminDate.day("2026-01-01")
        let estimates = (0..<80).map { _ in
            VO2maxEstimator.Estimate(
                date: first.adding(days: random.integer(0...200)),
                duration: random.uniform(900...7200), vo2max: random.uniform(35...65))
        }
        for offset in 0...230 {
            let day = first.adding(days: offset)
            let window = estimates.filter { $0.date <= day && $0.date.days(to: day) < 30 }
            let trend = VO2maxEstimator.trend(estimates, on: day)
            #expect((trend == nil) == window.isEmpty)
            if let trend {
                let weights = window.map(\.duration).reduce(0, +)
                let mean = window.map { $0.vo2max * $0.duration }.reduce(0, +) / weights
                #expect(AnalyticsBlackBox.isClose(trend, mean, tolerance: 1e-9))
            }
        }
    }

    @Test("The maximum heart rate of the running zones, else the default ones, else any")
    func maxHeartRate() {
        let running = AnalyticsBlackBox.zones("RUNNING", maximum: 192)
        let fallback = AnalyticsBlackBox.zones("DEFAULT", maximum: 185)
        let cycling = AnalyticsBlackBox.zones("CYCLING", maximum: 178)
        let unknown = AnalyticsBlackBox.zones("RUNNING", maximum: nil)
        #expect(VO2maxEstimator.maxHeartRate(from: [fallback, running, cycling]) == 192)
        #expect(VO2maxEstimator.maxHeartRate(from: [cycling, fallback]) == 185)
        #expect(VO2maxEstimator.maxHeartRate(from: [unknown, fallback]) == 185)
        #expect(VO2maxEstimator.maxHeartRate(from: [cycling]) == 178)
        #expect(VO2maxEstimator.maxHeartRate(from: [unknown]) == nil)
        #expect(VO2maxEstimator.maxHeartRate(from: []) == nil)
    }
}
