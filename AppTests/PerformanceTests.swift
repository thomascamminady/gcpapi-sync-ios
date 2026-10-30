import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

@Suite struct PerformanceTests {
    /// Daniels' tables: a VDOT of 50 runs 5 km in 19:57, 10 km in 41:21, the half marathon in
    /// 1:31:35 and the marathon in 3:10:49; 60 runs them in 17:03, 35:22, 1:18:09 and 2:42:33.
    /// The formula and the rounded tables differ by up to 0.6 %.
    @Test(arguments: [
        (50.0, 5000.0, 1197.0), (50, 10_000, 2481), (50, 21_097.5, 5495), (50, 42_195, 11_449),
        (60, 5000, 1023), (60, 10_000, 2122), (60, 21_097.5, 4689), (60, 42_195, 9753),
    ])
    func raceTimesMatchTheTables(vo2max: Double, metres: Double, seconds: Double) throws {
        let time = try #require(Performance.raceTime(metres: metres, vo2max: vo2max))
        #expect(abs(time - seconds) < 0.006 * seconds, "\(time)")
    }

    @Test func fitterIsFasterAndLongerIsSlower() throws {
        for metres in Performance.raceDistances {
            let slower = try #require(Performance.raceTime(metres: metres, vo2max: 45))
            let faster = try #require(Performance.raceTime(metres: metres, vo2max: 55))
            #expect(faster < slower)
        }
        let paces = Performance.predictions(vo2max: 52).map(\.metresPerSecond)
        #expect(paces.count == Performance.raceDistances.count)
        #expect(paces == paces.sorted(by: >))
    }

    @Test func noPredictionWithoutAVO2max() {
        #expect(Performance.raceTime(metres: 5000, vo2max: 0) == nil)
        #expect(Performance.raceTime(metres: 5000, vo2max: 150) == nil)
        #expect(Performance.raceTime(metres: 0, vo2max: 50) == nil)
        #expect(Performance.predictions(vo2max: .nan).isEmpty)
    }

    @Test func sustainableShareFallsWithTime() {
        #expect(abs(Performance.sustainableShare(minutes: 10) - 0.99) < 0.02)
        #expect(
            Performance.sustainableShare(minutes: 30) > Performance.sustainableShare(minutes: 60))
        #expect(Performance.sustainableShare(minutes: 600) > 0.8)
    }

    @Test(arguments: [20.0, 35, 50, 65, 80])
    func speedInvertsTheOxygenCost(oxygen: Double) throws {
        let speed = try #require(Performance.speed(oxygen: oxygen))
        #expect(abs(VO2maxEstimator.cost(metresPerMinute: speed) - oxygen) < 1e-9)
    }

    /// Daniels' tables for a VDOT of 50: threshold 4:15/km, interval 3:55/km.
    @Test func trainingPacesMatchTheTables() throws {
        let threshold = try #require(Performance.speeds(.threshold, vo2max: 50))
        let interval = try #require(Performance.speeds(.interval, vo2max: 50))
        #expect((1000 / threshold.upperBound...1000 / threshold.lowerBound).contains(255))
        #expect((1000 / interval.upperBound - 3)...(1000 / interval.lowerBound + 3) ~= 235)
        var previous = 0.0
        for intensity in Performance.Intensity.allCases {
            let speeds = try #require(Performance.speeds(intensity, vo2max: 50))
            #expect(speeds.lowerBound > previous)
            previous = speeds.upperBound
        }
        #expect(Performance.speeds(.easy, vo2max: 0) == nil)
    }
}

@Suite struct ActivityTotalsTests {
    private func workout(
        _ id: Int, on date: String, type: String = "running", minutes: Double = 30,
        metres: Double? = nil, heartRate: Double? = nil, ascent: Double? = nil,
        calories: Double? = nil, load: Double? = nil
    ) throws -> Workout {
        try #require(
            Workout(
                SummarizedActivity(
                    activityId: id,
                    startTimeLocal: (try? GarminTime(hour: 7)).map {
                        LocalDateTime(date: .day(date), time: $0)
                    },
                    activityType: ActivityType(typeKey: type), distance: metres,
                    duration: minutes * 60, elevationGain: ascent, calories: calories,
                    averageHR: heartRate, activityTrainingLoad: load)))
    }

    @Test func sums() throws {
        let totals = ActivityTotals([
            try workout(
                1, on: "2026-10-01", minutes: 30, metres: 6000, heartRate: 140, ascent: 20,
                calories: 300, load: 50),
            try workout(
                2, on: "2026-10-02", minutes: 60, metres: 10_000, heartRate: 150, ascent: 80,
                calories: 600, load: 120),
            try workout(
                3, on: "2026-10-03", type: "strength_training", minutes: 30, calories: 150, load: 20
            ),
        ])
        #expect(totals.activityCount == 3)
        #expect(totals.duration == 7200)
        #expect(totals.distance == 16_000)
        #expect(totals.durationWithDistance == 5400)
        #expect(totals.ascent == 100)
        #expect(totals.calories == 1050)
        #expect(totals.load == 190)
        // (140 · 30 + 150 · 60) / 90
        #expect(abs((totals.averageHeartRate ?? 0) - 146.6667) < 0.001)
        #expect(abs((totals.averageSpeed ?? 0) - 16_000 / 5400) < 1e-9)
    }

    @Test func nothingToSum() {
        let totals = ActivityTotals([])
        #expect(totals.activityCount == 0)
        #expect(totals.averageSpeed == nil)
        #expect(totals.averageHeartRate == nil)
    }

    @Test func monthsAreCalendarMonthsNewestFirst() throws {
        let workouts = [
            try workout(1, on: "2026-10-30", metres: 5000),
            try workout(2, on: "2026-10-01", metres: 5000),
            try workout(3, on: "2026-09-30", metres: 8000),
            try workout(4, on: "2026-07-15", metres: 3000),
            try workout(5, on: "2026-03-01", metres: 3000),
        ]
        let months = ActivityTotals.months(workouts, count: 4, through: .day("2026-10-30"))
        #expect(
            months.map(\.first)
                == ["2026-10-01", "2026-09-01", "2026-08-01", "2026-07-01"].map(GarminDate.day))
        #expect(months.map(\.totals.activityCount) == [2, 1, 0, 1])
        #expect(months[0].totals.distance == 10_000)
        #expect(ActivityTotals.months(workouts, count: 0, through: .day("2026-10-30")).isEmpty)
    }

    @Test func bySportFollowsTheSportOrder() throws {
        let workouts = [
            try workout(1, on: "2026-10-01", type: "strength_training"),
            try workout(2, on: "2026-10-01", type: "cycling"),
            try workout(3, on: "2026-10-02"),
            try workout(4, on: "2026-10-03"),
        ]
        let sports = ActivityTotals.bySport(workouts)
        #expect(
            sports.map(\.sport)
                == Sport.allCases.filter { [.running, .cycling, .strength].contains($0) })
        #expect(sports.first { $0.sport == .running }?.totals.activityCount == 2)
    }
}

@Suite struct LoadBalanceTests {
    @Test func monotonyIsTheMeanOverTheDeviation() throws {
        // Mean 50, sample standard deviation of [0, 100, 50, 50] is 40.82…
        let monotony = try #require(LoadBalance.monotony([0, 100, 50, 50]))
        #expect(abs(monotony - 50 / (5000.0 / 3).squareRoot()) < 1e-9)
        let strain = try #require(LoadBalance.strain([0, 100, 50, 50]))
        #expect(abs(strain - 200 * monotony) < 1e-9)
    }

    @Test func noMonotonyWithoutVariation() {
        #expect(LoadBalance.monotony([60, 60, 60]) == nil)
        #expect(LoadBalance.monotony([60]) == nil)
        #expect(LoadBalance.monotony([]) == nil)
        #expect(LoadBalance.strain([]) == nil)
    }

    @Test func alikeDaysAreMoreMonotonous() throws {
        let alike = try #require(LoadBalance.monotony([60, 70, 60, 70, 60, 70, 60]))
        let varied = try #require(LoadBalance.monotony([0, 150, 0, 100, 0, 200, 0]))
        #expect(alike > 2)
        #expect(varied < 1)
    }

    @Test func workloadRatio() {
        let day = TrainingLoad.Day(date: .day("2026-10-30"), load: 0, fitness: 60, fatigue: 75)
        #expect(LoadBalance.workloadRatio(day) == 1.25)
        let fresh = TrainingLoad.Day(date: .day("2026-10-30"), load: 0, fitness: 0, fatigue: 5)
        #expect(LoadBalance.workloadRatio(fresh) == nil)
    }
}
