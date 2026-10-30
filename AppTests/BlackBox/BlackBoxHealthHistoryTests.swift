import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A history of consecutive days from the reference date, one entry per value.
private func history(steps: [Int?]) -> HealthHistory {
    HealthHistory(
        days: zip(
            AnalyticsBlackBox.dates(from: AnalyticsBlackBox.reference, count: steps.count), steps
        ).map {
            DayHealth(date: $0, steps: $1)
        })
}

@Suite("Health history: aggregates")
struct BlackBoxHealthAggregateTests {
    @Test("The mean over the days that have the metric")
    func average() {
        #expect(history(steps: [100, 200, nil, 300]).average(\.steps) == 200)
        #expect(history(steps: [nil, 8000]).average(\.steps) == 8000)
        #expect([1, 2].contains(history(steps: [1, 2]).average(\.steps) ?? 0))
        #expect([1, 2].contains(history(steps: [1, 2, 2]).average(\.steps) ?? 0))
        #expect(history(steps: [nil, nil]).average(\.steps) == nil)
        #expect(history(steps: []).average(\.steps) == nil)
    }

    @Test("Random averages lie within a unit of the exact mean")
    func randomAverages() {
        var random = BlackBoxRandom(seed: 4)
        for _ in 0..<50 {
            let steps = (0..<random.integer(1...40)).map { _ -> Int? in
                random.uniform(0...1) < 0.3 ? nil : random.integer(0...30_000)
            }
            let present = steps.compactMap(\.self)
            let average = history(steps: steps).average(\.steps)
            if present.isEmpty {
                #expect(average == nil)
            } else {
                let mean = Double(present.reduce(0, +)) / Double(present.count)
                #expect(abs(Double(average ?? -1_000_000) - mean) < 1)
            }
        }
    }

    @Test("The latest value is the most recent day's that has one")
    func latest() {
        #expect(history(steps: [5, 7, nil]).latest(\.steps) == 7)
        #expect(history(steps: [5, nil, 9]).latest(\.steps) == 9)
        #expect(history(steps: [nil, nil]).latest(\.steps) == nil)
        let days = AnalyticsBlackBox.dates(from: AnalyticsBlackBox.reference, count: 3)
        let statuses = HealthHistory(days: [
            DayHealth(date: days[0], hrvStatus: "LOW"),
            DayHealth(date: days[1], hrvStatus: "BALANCED"),
            DayHealth(date: days[2]),
        ])
        #expect(statuses.latest(\.hrvStatus) == "BALANCED")
    }

    @Test("The mean of a fractional metric over the days that have it")
    func mean() throws {
        let days = AnalyticsBlackBox.dates(from: AnalyticsBlackBox.reference, count: 4)
        let history = HealthHistory(days: [
            DayHealth(date: days[0], vo2max: 50.5), DayHealth(date: days[1]),
            DayHealth(date: days[2], vo2max: 49.5), DayHealth(date: days[3], vo2max: 52),
        ])
        #expect(AnalyticsBlackBox.isClose(try #require(history.mean(\.vo2max)), 152.0 / 3))
        #expect(HealthHistory(days: [DayHealth(date: days[0])]).mean(\.vo2max) == nil)
    }

    @Test("The total over the days that have the metric, zero without any")
    func total() {
        #expect(history(steps: [100, nil, 250]).total(\.steps) == 350)
        #expect(history(steps: [nil]).total(\.steps) == 0)
        #expect(history(steps: []).total(\.steps) == 0)
    }

    @Test("The average night: mean duration, and mean score of the scored nights")
    func averageSleep() throws {
        let days = AnalyticsBlackBox.dates(from: AnalyticsBlackBox.reference, count: 4)
        let history = HealthHistory(days: [
            DayHealth(date: days[0], sleep: AnalyticsBlackBox.night(hours: 8, score: 80)),
            DayHealth(date: days[1]),
            DayHealth(date: days[2], sleep: AnalyticsBlackBox.night(hours: 6, score: nil)),
            DayHealth(date: days[3], sleep: AnalyticsBlackBox.night(hours: 7, score: 70)),
        ])
        let night = try #require(history.averageSleep)
        #expect(night.total == 7 * 3600)
        #expect(night.score == 75)
        let unscored = HealthHistory(days: [
            DayHealth(date: days[0], sleep: AnalyticsBlackBox.night(hours: 5, score: nil))
        ])
        #expect(unscored.averageSleep?.total == 5 * 3600)
        #expect(unscored.averageSleep?.score == nil)
        #expect(HealthHistory(days: [DayHealth(date: days[0])]).averageSleep == nil)
    }

    @Test("A day is identified by its date and starts at local midnight")
    func dayIdentity() {
        let day = DayHealth(date: AnalyticsBlackBox.reference)
        #expect(day.id == AnalyticsBlackBox.reference)
        #expect(day.start == AnalyticsBlackBox.reference.startOfDay(in: .current))
    }
}

@Suite("Health loader: assembling Garmin's responses")
struct BlackBoxHealthAssembleTests {
    private let dates = AnalyticsBlackBox.dates(from: .day("2026-10-24"), count: 7)

    private func summary(
        _ date: GarminDate, steps: Int? = 9000, stress: Int? = 30, moderate: Int? = 20,
        vigorous: Int? = 10
    ) -> UserDailySummaryV2 {
        UserDailySummaryV2(
            calendarDate: date,
            movement: MovementV2(steps: MovementValueV2(goal: 10_000, value: steps)),
            calories: CaloriesV2(burnedActive: 650),
            heartRate: HeartRateV2(restingValue: 48),
            intensityMinutes: IntensityMinutesV2(moderate: moderate, vigorous: vigorous),
            stress: StressV2(avgLevel: stress),
            bodyBattery: BodyBatteryV2(minValue: 15, maxValue: 90))
    }

    private func sleep(_ date: GarminDate) -> DailySleep {
        DailySleep(
            calendarDate: date, sleepTimeSeconds: 27_000, deepSleepSeconds: 5400,
            lightSleepSeconds: 14_400, remSleepSeconds: 7200, awakeSleepSeconds: 1200,
            sleepScores: SleepScores(overall: SleepScoreItem(value: 82)))
    }

    private func hrv(_ date: GarminDate) -> HrvSummary {
        HrvSummary(calendarDate: date, lastNightAvg: 61, status: "BALANCED")
    }

    @Test("One day per date, each metric from its response")
    func complete() throws {
        let history = HealthLoader.assemble(
            dates: dates, summaries: dates.map { summary($0) }, sleep: dates.map(sleep),
            hrv: dates.map(hrv))
        #expect(history.days.map(\.date) == dates)
        let day = try #require(history.days.first)
        #expect(day.steps == 9000)
        #expect(day.stepGoal == 10_000)
        #expect(day.restingHeartRate == 48)
        #expect(day.stress == 30)
        #expect(day.bodyBatteryLow == 15)
        #expect(day.bodyBatteryHigh == 90)
        #expect(day.activeCalories == 650)
        #expect(day.intensityMinutes == 40)
        #expect(day.hrv == 61)
        #expect(day.hrvStatus == "BALANCED")
        let night = try #require(day.sleep)
        #expect(night.total == 27_000)
        #expect(night.deep == 5400)
        #expect(night.light == 14_400)
        #expect(night.rem == 7200)
        #expect(night.awake == 1200)
        #expect(night.score == 82)
    }

    @Test("Days Garmin missed are there, without data")
    func missingDays() throws {
        let history = HealthLoader.assemble(
            dates: dates, summaries: [summary(dates[1])], sleep: [sleep(dates[3])],
            hrv: [hrv(dates[5])])
        #expect(history.days.map(\.date) == dates)
        #expect(
            history.days.map { $0.steps != nil } == [
                false, true, false, false, false, false, false,
            ])
        #expect(
            history.days.map { $0.sleep != nil } == [
                false, false, false, true, false, false, false,
            ])
        #expect(
            history.days.map { $0.hrv != nil } == [false, false, false, false, false, true, false])
        let empty = try #require(history.days.first)
        #expect(empty == DayHealth(date: dates[0]))
    }

    @Test("Responses in any order land on their own dates; others are ignored")
    func order() {
        let outside = GarminDate.day("2026-09-01")
        let summaries = (dates.reversed() + [outside]).map { summary($0, steps: $0.day * 100) }
        let history = HealthLoader.assemble(dates: dates, summaries: summaries, sleep: [], hrv: [])
        #expect(history.days.map(\.steps) == dates.map { $0.day * 100 })
    }

    @Test("A negative stress level means not enough data", arguments: [-1, -2])
    func negativeStress(level: Int) {
        let history = HealthLoader.assemble(
            dates: [dates[0]], summaries: [summary(dates[0], stress: level)], sleep: [], hrv: [])
        #expect(history.days.first?.stress == nil)
    }

    @Test(
        "Intensity minutes: moderate plus twice vigorous",
        arguments: [(20, 10, 40), (0, 15, 30), (45, 0, 45)] as [(Int?, Int?, Int)])
    func intensity(moderate: Int?, vigorous: Int?, expected: Int) {
        let history = HealthLoader.assemble(
            dates: [dates[0]],
            summaries: [summary(dates[0], moderate: moderate, vigorous: vigorous)], sleep: [],
            hrv: [])
        #expect(history.days.first?.intensityMinutes == expected)
    }

    @Test("VO2max from the runs of the 30 days ending on each day")
    func vo2max() throws {
        let runDay = dates[2]
        let run = AnalyticsBlackBox.activity(
            id: 5, on: runDay, duration: 3000, distance: 10_000, speed: 200.0 / 60,
            gradeAdjusted: 200.0 / 60, heartRate: 160, maxHeartRate: 168)
        let zones = [AnalyticsBlackBox.zones("RUNNING", maximum: 190)]
        let history = HealthLoader.assemble(
            dates: dates, summaries: [], sleep: [], hrv: [], runs: [run], zones: zones)
        let estimate = try #require(VO2maxEstimator.estimate(run, maxHeartRate: 190))
        for day in history.days {
            if day.date < runDay {
                #expect(day.vo2max == nil)
            } else {
                #expect(AnalyticsBlackBox.isClose(try #require(day.vo2max), estimate.vo2max))
            }
        }
        let withoutZones = HealthLoader.assemble(
            dates: dates, summaries: [], sleep: [], hrv: [], runs: [run], zones: [])
        #expect(withoutZones.days.allSatisfy { $0.vo2max == nil })
    }
}

@Suite("Sample data")
struct BlackBoxSampleDataTests {
    @Test("A sample day is deterministic and plausible", arguments: 0..<40)
    func sampleDay(offset: Int) throws {
        let date = GarminDate.day("2026-01-01").adding(days: offset * 9)
        let day = DayHealth.sample(for: date)
        #expect(day == DayHealth.sample(for: date))
        #expect(day.date == date)
        #expect((0...100_000).contains(try #require(day.steps)))
        #expect((30...100).contains(try #require(day.restingHeartRate)))
        #expect((10...200).contains(try #require(day.hrv)))
        #expect((0...100).contains(try #require(day.stress)))
        let low = try #require(day.bodyBatteryLow)
        let high = try #require(day.bodyBatteryHigh)
        #expect(0 <= low && low <= high && high <= 100)
        let night = try #require(day.sleep)
        #expect((3 * 3600...12 * 3600).contains(night.total))
        #expect(night.deep >= 0 && night.light >= 0 && night.rem >= 0 && night.awake >= 0)
        #expect(night.deep + night.light + night.rem <= night.total + night.awake)
        #expect((0...100).contains(try #require(night.score)))
    }

    @Test("A sample history: the days ending on a date, oldest first", arguments: [1, 7, 30, 90])
    func sampleHistory(days: Int) {
        let end = AnalyticsBlackBox.reference
        let history = HealthHistory.sample(endingOn: end, days: days)
        #expect(
            history.days.map(\.date)
                == AnalyticsBlackBox.dates(from: end.adding(days: 1 - days), count: days))
        #expect(history == HealthHistory.sample(endingOn: end, days: days))
        #expect(HealthHistory.sample(endingOn: end).days.count == 7)
    }

    @Test("Sample training: consistent with what the training screens expect")
    func sampleTraining() throws {
        let end = AnalyticsBlackBox.reference
        let data = TrainingData.sample(endingOn: end)
        #expect(data == TrainingData.sample(endingOn: end))
        #expect(!data.workouts.isEmpty)
        #expect(data.workouts.allSatisfy { $0.date <= end })
        #expect(zip(data.workouts, data.workouts.dropFirst()).allSatisfy { $0.date >= $1.date })
        let ids = data.workouts.map(\.id)
        #expect(Set(ids).count == ids.count)
        let history = data.loadHistory.map(\.date)
        #expect(history.last == end)
        #expect(
            history
                == AnalyticsBlackBox.dates(from: try #require(history.first), count: history.count))
        #expect(data.load == Array(data.loadHistory.suffix(TrainingLoader.shownDays)))
        #expect(!data.weeks.isEmpty)
        #expect(
            zip(data.weeks, data.weeks.dropFirst()).allSatisfy {
                $0.start.adding(days: 7) == $1.start
            })
        #expect(data.loadHistory.allSatisfy { $0.fitness >= 0 && $0.fatigue >= 0 && $0.load >= 0 })
    }
}
