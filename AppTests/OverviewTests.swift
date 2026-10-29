import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

@Suite struct VO2maxEstimatorTests {
    private let monday = GarminDate.day("2026-10-19")

    /// A run on `date` at `metresPerMinute`, with an average heart rate of `heartRate`.
    private func run(
        on date: GarminDate, metresPerMinute: Double = 200, heartRate: Double? = 160.2,
        minutes: Double = 40, type: String = "running"
    ) -> SummarizedActivity {
        SummarizedActivity(
            activityId: 1,
            startTimeLocal: (try? GarminTime(hour: 7)).map { LocalDateTime(date: date, time: $0) },
            activityType: ActivityType(typeKey: type),
            distance: metresPerMinute * minutes,
            duration: minutes * 60,
            averageSpeed: metresPerMinute / 60 + 1,
            averageHR: heartRate,
            avgGradeAdjustedSpeed: metresPerMinute / 60
        )
    }

    @Test func oxygenCostOfRunning() {
        #expect(abs(VO2maxEstimator.cost(metresPerMinute: 200) - 36.0116) < 1e-9)
    }

    @Test func aSteadyRunEstimatesVO2max() throws {
        // 160.2 of 180 bpm is 89 % of the maximum, or 81.25 % of VO2max.
        let estimate = try #require(
            VO2maxEstimator.estimate(run(on: monday, type: "trail_running"), maxHeartRate: 180))
        #expect(estimate.date == monday)
        #expect(estimate.duration == 2400)
        #expect(abs(estimate.vo2max - 36.0116 / 0.8125) < 1e-9)
    }

    @Test func gradeAdjustedSpeedIsPreferred() throws {
        var flat = run(on: monday)
        flat.avgGradeAdjustedSpeed = nil
        let estimate = try #require(VO2maxEstimator.estimate(flat, maxHeartRate: 180))
        #expect(estimate.vo2max > 36.0116 / 0.8125)
    }

    @Test func unsuitableRunsAreSkipped() {
        var undated = run(on: monday)
        undated.startTimeLocal = nil
        var short = run(on: monday)
        short.distance = 2000
        for activity in [
            run(on: monday, type: "cycling"), run(on: monday, minutes: 10), short, undated,
            run(on: monday, heartRate: nil), run(on: monday, heartRate: 90),
            run(on: monday, heartRate: 185),
        ] {
            #expect(VO2maxEstimator.estimate(activity, maxHeartRate: 180) == nil)
        }
        #expect(VO2maxEstimator.estimate(run(on: monday), maxHeartRate: 0) == nil)
    }

    @Test func trendWeighsRunsByDuration() {
        let estimates = [
            VO2maxEstimator.Estimate(date: monday.adding(days: -30), duration: 9000, vo2max: 30),
            VO2maxEstimator.Estimate(date: monday.adding(days: -29), duration: 1800, vo2max: 50),
            VO2maxEstimator.Estimate(date: monday, duration: 3600, vo2max: 56),
            VO2maxEstimator.Estimate(date: monday.adding(days: 1), duration: 9000, vo2max: 70),
        ]
        #expect(VO2maxEstimator.trend(estimates, on: monday) == 54)
        #expect(VO2maxEstimator.trend(estimates, on: monday.adding(days: -40)) == nil)
    }

    @Test func runningZonesSetTheMaximumHeartRate() {
        let cycling = HeartRateZones(maxHeartRateUsed: 175, sport: "CYCLING")
        let fallback = HeartRateZones(maxHeartRateUsed: 185, sport: "DEFAULT")
        let running = HeartRateZones(maxHeartRateUsed: 190, sport: "RUNNING")
        #expect(VO2maxEstimator.maxHeartRate(from: [cycling, fallback, running]) == 190)
        #expect(VO2maxEstimator.maxHeartRate(from: [cycling, fallback]) == 185)
        #expect(VO2maxEstimator.maxHeartRate(from: [cycling]) == 175)
        #expect(VO2maxEstimator.maxHeartRate(from: []) == nil)
    }

    @Test func assembleEstimatesEachDay() {
        let tuesday = monday.adding(days: 1)
        let week = HealthLoader.assemble(
            dates: [monday, tuesday], summaries: [], sleep: [], hrv: [],
            runs: [run(on: tuesday)], zones: [HeartRateZones(maxHeartRateUsed: 180)])
        #expect(week.days[0].vo2max == nil)
        #expect(week.days[1].vo2max.map { abs($0 - 36.0116 / 0.8125) < 1e-9 } == true)
        let withoutZones = HealthLoader.assemble(
            dates: [tuesday], summaries: [], sleep: [], hrv: [], runs: [run(on: tuesday)])
        #expect(withoutZones.days[0].vo2max == nil)
    }
}

@Suite struct OverviewTests {
    private let monday = GarminDate.day("2026-10-19")

    private func days(restingHeartRate: [Int?]) -> [DayHealth] {
        restingHeartRate.enumerated().map { offset, value in
            var day = DayHealth(date: monday.adding(days: offset))
            day.restingHeartRate = value
            return day
        }
    }

    @Test func valuesAreScaledToTheirRange() {
        let scaled = OverviewMetric.restingHeartRate.scaled(
            days(restingHeartRate: [50, nil, 40, 45]))
        #expect(scaled.map(\.date) == [monday, monday.adding(days: 2), monday.adding(days: 3)])
        #expect(scaled.map(\.value) == [50, 40, 45])
        #expect(scaled.map(\.scaled) == [1, 0, 0.5])
    }

    @Test func averagingTakesTheDaysEndingOnEachDay() {
        // The first two days only lead in; days without a value stay off the chart.
        let scaled = OverviewMetric.restingHeartRate.scaled(
            days(restingHeartRate: [40, 50, 60, nil, 44, 46]), averaging: 3)
        #expect(scaled.map(\.date) == [2, 4, 5].map { monday.adding(days: $0) })
        #expect(scaled.map(\.value) == [50, 52, 45])
        #expect(scaled.map(\.scaled) == [5.0 / 7, 1, 0])
    }

    @Test func higherIsBetterFlipsWhatIsBetterLow() {
        let week = days(restingHeartRate: [50, 40])
        #expect(
            OverviewMetric.restingHeartRate.scaled(week, higherIsBetter: true).map(\.scaled)
                == [0, 1])
        var hrv = week
        hrv[0].hrv = 70
        hrv[1].hrv = 60
        #expect(OverviewMetric.hrv.scaled(hrv, higherIsBetter: true).map(\.scaled) == [1, 0])
    }

    @Test func aFlatOrEmptyMetric() {
        #expect(
            OverviewMetric.restingHeartRate.scaled(days(restingHeartRate: [45, 45])).map(\.scaled)
                == [0.5, 0.5])
        #expect(OverviewMetric.vo2max.scaled(days(restingHeartRate: [45])).isEmpty)
    }

    @Test(arguments: OverviewMetric.allCases)
    func everyMetricIsPresentable(metric: OverviewMetric) {
        let day = DayHealth.sample(for: monday)
        let value = metric.value(of: day)
        #expect(value != nil)
        #expect(!metric.title.isEmpty)
        #expect(!metric.symbol.isEmpty)
        #expect(metric.formatted(value) != "–")
        #expect(metric.formatted(nil) == "–")
        #expect(metric.lowerIsBetter == [.restingHeartRate, .stress].contains(metric))
        let scaled = metric.scaled(HealthHistory.sample(endingOn: monday, days: 30).days)
        #expect(scaled.count == 30)
        #expect(scaled.allSatisfy { (0...1).contains($0.scaled) })
        #expect(scaled.contains { $0.scaled == 0 } && scaled.contains { $0.scaled == 1 })
    }

    @Test func formatting() {
        #expect(OverviewMetric.vo2max.formatted(52.04) == "\(Format.decimal(52.04)) ml/kg/min")
        #expect(OverviewMetric.hrv.formatted(61.6) == "62 ms")
        #expect(OverviewMetric.restingHeartRate.formatted(44) == "44 bpm")
        #expect(OverviewMetric.stress.formatted(31) == "31")
        #expect(Format.decimal(nil) == "–")
    }
}
