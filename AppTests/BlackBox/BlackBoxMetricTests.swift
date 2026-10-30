import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Days to present: one with every value, one with none.
enum BlackBoxDays {
    nonisolated static let sleep = SleepNight(
        total: 27_120, deep: 5400, light: 15_600, rem: 6120, awake: 1800, score: 82
    )

    nonisolated static func full(_ date: GarminDate) -> DayHealth {
        DayHealth(
            date: date, steps: 12_345, stepGoal: 10_000, restingHeartRate: 52, hrv: 45,
            hrvStatus: "BALANCED", sleep: sleep, stress: 30, bodyBatteryLow: 20,
            bodyBatteryHigh: 90, activeCalories: 600, intensityMinutes: 45, vo2max: 52.3
        )
    }

    /// `count` days ending today, each made by `make`.
    nonisolated static func week(
        count: Int = 7, _ make: (GarminDate) -> DayHealth
    ) -> HealthHistory {
        let today = BlackBox.today
        return HealthHistory(days: (0..<count).reversed().map { make(today.adding(days: -$0)) })
    }

    /// The same values every day.
    nonisolated static func constant(_ date: GarminDate) -> DayHealth {
        DayHealth(
            date: date, steps: 10_000, restingHeartRate: 50, hrv: 60,
            sleep: SleepNight(total: 28_800, deep: 7200, light: 14_400, rem: 7200, awake: 0),
            stress: 30, bodyBatteryLow: 20, bodyBatteryHigh: 90, intensityMinutes: 20,
            vo2max: 50
        )
    }
}

/// Everything the dashboard needs to present a metric.
@Suite struct BlackBoxMetricTests {
    // MARK: - Presentable

    @Test func everyMetricIsListedOnce() {
        #expect(Metric.allCases.count == 8)
        #expect(Set(Metric.allCases).count == 8)
        #expect(Set(Metric.allCases.map(\.rawValue)).count == 8)
    }

    @Test func everyMetricIsPresentable() {
        for metric in Metric.allCases {
            #expect(!metric.title.isEmpty, "\(metric)")
            #expect(!metric.shortTitle.isEmpty, "\(metric)")
            #expect(metric.shortTitle.count <= metric.title.count, "\(metric)")
            #expect(!metric.explanation.isEmpty, "\(metric)")
            #expect(BlackBox.isSymbol(metric.symbol), "\(metric.symbol)")
            #expect(metric.id == metric)
            #expect(Metric(rawValue: metric.rawValue) == metric)
        }
    }

    @Test func titlesTellMetricsApart() {
        #expect(Set(Metric.allCases.map(\.title)).count == Metric.allCases.count)
        #expect(Set(Metric.allCases.map(\.shortTitle)).count == Metric.allCases.count)
    }

    @Test func tintIsTheUsersColorOfTheMetric() {
        for metric in Metric.allCases {
            #expect(metric.tint.hex == ColorRole.metric(metric).color.hex, "\(metric)")
            #expect(ColorRole.metric(metric).hue == metric.hue, "\(metric)")
        }
    }

    @Test func heartRateIsRedInTheChartsToo() {
        #expect(TrackMeasure.heartRate.hue == Metric.restingHeartRate.hue)
        #expect(TrackMeasure.heartRate.hue == .red)
        #expect(TrackMeasure.elevation.hue == .brown)
    }

    @Test func amountsHaveBarsAndLevelsLines() {
        #expect(Metric.steps.isAmount)
        #expect(Metric.intensityMinutes.isAmount)
        #expect(!Metric.restingHeartRate.isAmount)
        #expect(!Metric.hrv.isAmount)
        #expect(!Metric.vo2max.isAmount)
        #expect(!Metric.stress.isAmount)
    }

    @Test func unitsOfHeartMetrics() {
        #expect(Metric.restingHeartRate.unit?.lowercased().contains("bpm") == true)
        #expect(Metric.hrv.unit == "ms")
    }

    // MARK: - A day's value

    @Test func aDayWithoutDataHasNoValues() {
        let day = DayHealth(date: BlackBox.today)
        for metric in Metric.allCases {
            #expect(!metric.hasValue(day), "\(metric)")
            #expect(metric.value(of: day) == BlackBox.dash, "\(metric)")
            #expect(metric.number(of: day) == nil, "\(metric)")
            #expect(metric.summary(of: day).value == BlackBox.dash, "\(metric)")
        }
    }

    @Test func aDayWithEveryValueHasThemAll() {
        let day = BlackBoxDays.full(BlackBox.today)
        for metric in Metric.allCases {
            #expect(metric.hasValue(day), "\(metric)")
            #expect(metric.value(of: day) != BlackBox.dash, "\(metric)")
            #expect(metric.number(of: day) != nil, "\(metric)")
        }
    }

    @Test(arguments: [
        (Metric.steps, "12345"), (.restingHeartRate, "52"), (.hrv, "45"), (.stress, "30"),
        (.intensityMinutes, "45"), (.vo2max, "523"), (.sleep, "732"),
    ])
    func aDaysValueShowsItsNumber(metric: Metric, digits: String) {
        let day = BlackBoxDays.full(BlackBox.today)
        #expect(BlackBox.digits(metric.value(of: day)) == digits)
    }

    @Test(arguments: [
        (Metric.steps, 12_345.0), (.restingHeartRate, 52), (.hrv, 45), (.stress, 30),
        (.intensityMinutes, 45), (.vo2max, 52.3),
    ])
    func aDaysNumberIsItsValue(metric: Metric, number: Double) throws {
        let day = BlackBoxDays.full(BlackBox.today)
        let value = try #require(metric.number(of: day))
        #expect(abs(value - number) < 0.001)
    }

    @Test func bodyBatteryShowsItsCharge() {
        let day = BlackBoxDays.full(BlackBox.today)
        #expect(Metric.bodyBattery.value(of: day).contains("90"))
    }

    @Test func aDayWithOnlyStepsHasOnlySteps() {
        let day = DayHealth(date: BlackBox.today, steps: 4321)
        for metric in Metric.allCases {
            #expect(metric.hasValue(day) == (metric == .steps), "\(metric)")
        }
    }

    @Test func aDaysHeadlineIsItsValue() {
        let day = BlackBoxDays.full(BlackBox.today)
        for metric in Metric.allCases {
            #expect(metric.summary(of: day).value == metric.value(of: day), "\(metric)")
            #expect(metric.summary(of: day).unit == metric.unit, "\(metric)")
        }
    }

    @Test func valuesNumbersAndHasValueAgreeOnSampleDays() {
        let history = HealthHistory.sample(endingOn: BlackBox.today, days: 30)
        for day in history.days {
            for metric in Metric.allCases {
                let has = metric.hasValue(day)
                #expect(has == (metric.value(of: day) != BlackBox.dash), "\(metric) \(day.date)")
                #expect(has == (metric.number(of: day) != nil), "\(metric) \(day.date)")
            }
        }
    }

    // MARK: - A run of days

    @Test func anEmptyHistoryHasNoHeadline() {
        let history = HealthHistory(days: [])
        for metric in Metric.allCases where metric != .intensityMinutes {
            #expect(metric.summary(of: history).value == BlackBox.dash, "\(metric)")
        }
        let intensity = Metric.intensityMinutes.summary(of: history).value
        #expect(intensity == BlackBox.dash || BlackBox.digits(intensity) == "0")
    }

    @Test(arguments: [
        (Metric.steps, "10000"), (.restingHeartRate, "50"), (.hrv, "60"), (.stress, "30"),
    ])
    func aConstantWeeksHeadlineIsTheConstant(metric: Metric, digits: String) {
        let history = BlackBoxDays.week(BlackBoxDays.constant)
        #expect(BlackBox.digits(metric.summary(of: history).value) == digits)
    }

    @Test func aConstantWeeksOtherHeadlines() {
        let history = BlackBoxDays.week(BlackBoxDays.constant)
        #expect(BlackBox.digits(Metric.vo2max.summary(of: history).value).hasPrefix("50"))
        #expect(BlackBox.digits(Metric.sleep.summary(of: history).value).hasPrefix("8"))
        #expect(Metric.bodyBattery.summary(of: history).value.contains("90"))
        let intensity = BlackBox.digits(Metric.intensityMinutes.summary(of: history).value)
        #expect(intensity == "20" || intensity == "140")
    }

    @Test func everyHeadlineHasContext() {
        let history = HealthHistory.sample(endingOn: BlackBox.today, days: 7)
        for metric in Metric.allCases {
            let summary = metric.summary(of: history)
            #expect(!summary.value.isEmpty, "\(metric)")
            #expect(summary.value != BlackBox.dash, "\(metric)")
        }
    }

    // MARK: - Tiles

    @Test func aTileWithoutDataIsNil() {
        let empty = HealthHistory(days: [])
        let blank = BlackBoxDays.week { DayHealth(date: $0) }
        for metric in Metric.allCases where metric != .intensityMinutes {
            #expect(metric.tile(of: empty) == nil, "\(metric)")
            #expect(metric.tile(of: blank) == nil, "\(metric)")
        }
        // Intensity minutes count per week, so a week without any may count zero.
        for history in [empty, blank] {
            if let tile = Metric.intensityMinutes.tile(of: history) {
                #expect(BlackBox.digits(tile.value) == "0")
            }
        }
    }

    @Test(arguments: [Metric.steps, .restingHeartRate, .hrv, .stress, .vo2max, .sleep])
    func aTileShowsTheLatestDayWithAValue(metric: Metric) throws {
        // Only the day three days ago has data.
        let target = BlackBox.today.adding(days: -3)
        let history = BlackBoxDays.week { date in
            date == target ? BlackBoxDays.full(date) : DayHealth(date: date)
        }
        let tile = try #require(metric.tile(of: history))
        #expect(tile.value == metric.value(of: BlackBoxDays.full(target)))
        #expect(tile.detail.contains(Metric.when(target, metric: metric)))
    }

    @Test func aTileShowsTodayWhenTodayHasAValue() throws {
        let history = BlackBoxDays.week(BlackBoxDays.full)
        let tile = try #require(Metric.steps.tile(of: history))
        #expect(tile.detail.contains(Metric.when(BlackBox.today, metric: .steps)))
        #expect(tile.value == Metric.steps.value(of: BlackBoxDays.full(BlackBox.today)))
    }

    @Test func intensityMinutesCountPerWeek() throws {
        let history = BlackBoxDays.week(BlackBoxDays.constant)
        let tile = try #require(Metric.intensityMinutes.tile(of: history))
        // The last seven days, or the days of this calendar week.
        let today = BlackBox.today
        let start = TrainingWeek.weekStart(of: today, calendar: .app)
        let thisWeek = 20 * (start.days(to: today) + 1)
        let digits = BlackBox.digits(tile.value)
        #expect(digits == "140" || digits == "\(thisWeek)")
    }

    // MARK: - When

    @Test func whenToday() {
        let today = BlackBox.today
        for metric in [Metric.steps, .stress, .intensityMinutes] {
            #expect(Metric.when(today, metric: metric) == "Today", "\(metric)")
        }
        #expect(Metric.when(today, metric: .sleep) == "Last night")
        for metric in Metric.allCases {
            #expect(["Today", "Last night"].contains(Metric.when(today, metric: metric)))
        }
    }

    @Test func whenYesterday() {
        let yesterday = BlackBox.today.adding(days: -1)
        for metric in [Metric.steps, .stress, .intensityMinutes, .restingHeartRate] {
            #expect(Metric.when(yesterday, metric: metric) == "Yesterday", "\(metric)")
        }
    }

    @Test(arguments: [2, 3, 4, 5, 6])
    func whenEarlierThisWeekIsTheWeekday(daysAgo: Int) {
        let date = BlackBox.today.adding(days: -daysAgo)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date.startOfDay(in: .current))
        let names = [
            calendar.weekdaySymbols[weekday - 1], calendar.standaloneWeekdaySymbols[weekday - 1],
        ]
        for metric in Metric.allCases {
            #expect(names.contains(Metric.when(date, metric: metric)), "\(metric)")
        }
    }
}

/// How far back a detail screen looks.
@Suite struct BlackBoxHistoryRangeTests {
    @Test func rangesAreAWeekAMonthAndAQuarter() {
        #expect(HistoryRange.allCases == [.week, .month, .quarter])
        #expect(HistoryRange.allCases.map(\.days) == [7, 30, 90])
    }

    @Test func rangesArePresentable() {
        for range in HistoryRange.allCases {
            #expect(!range.label.isEmpty)
            #expect(!range.caption.isEmpty)
            #expect(range.id == range)
            #expect(HistoryRange(rawValue: range.rawValue) == range)
        }
        #expect(Set(HistoryRange.allCases.map(\.label)).count == 3)
        #expect(Set(HistoryRange.allCases.map(\.caption)).count == 3)
    }

    @Test func everyDetailDaysSettingIsARange() {
        let days = Set(HistoryRange.allCases.map(\.days))
        #expect(days.contains(Settings().detailDays))
        #expect(HealthModel.dashboardDays == HistoryRange.week.days)
    }
}
