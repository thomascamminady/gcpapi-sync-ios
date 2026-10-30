import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// Time zones with unusual offsets or daylight saving transitions at midnight.
nonisolated private let zones = [
    "UTC", "Europe/Berlin", "America/Los_Angeles", "Pacific/Kiritimati", "Pacific/Pago_Pago",
    "America/Havana", "Asia/Beirut", "America/Santiago", "Australia/Lord_Howe",
    "Asia/Kathmandu",
]

/// Days around daylight saving transitions (some at midnight) and year ends.
nonisolated private let awkwardDates = [
    "2026-03-08", "2026-03-29", "2026-09-06", "2026-10-25", "2026-11-01", "2026-12-31",
    "2027-01-01", "2024-02-29", "2026-04-05", "2026-10-04",
]

@Suite("Training weeks: the first day of a week")
struct BlackBoxWeekStartTests {
    @Test(
        "The week of Friday 2026-10-30 by first weekday",
        arguments: [
            (1, "2026-10-25"), (2, "2026-10-26"), (3, "2026-10-27"), (4, "2026-10-28"),
            (5, "2026-10-29"), (6, "2026-10-30"), (7, "2026-10-24"),
        ])
    func fridayWeek(firstWeekday: Int, start: String) {
        let calendar = AnalyticsBlackBox.calendar(firstWeekday: firstWeekday)
        #expect(
            TrainingWeek.weekStart(of: AnalyticsBlackBox.reference, calendar: calendar)
                == .day(start))
    }

    @Test("A week's first day starts its own week")
    func firstDayIsItsOwnStart() {
        let monday = GarminDate.day("2026-10-26")
        let sunday = GarminDate.day("2026-11-01")
        let mondays = AnalyticsBlackBox.calendar(firstWeekday: 2)
        let sundays = AnalyticsBlackBox.calendar(firstWeekday: 1)
        #expect(TrainingWeek.weekStart(of: monday, calendar: mondays) == monday)
        #expect(TrainingWeek.weekStart(of: sunday, calendar: mondays) == monday)
        #expect(TrainingWeek.weekStart(of: sunday, calendar: sundays) == sunday)
        #expect(TrainingWeek.weekStart(of: monday, calendar: sundays) == .day("2026-10-25"))
    }

    @Test("The ISO 8601 calendar starts weeks on Monday")
    func isoCalendar() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        #expect(
            TrainingWeek.weekStart(of: AnalyticsBlackBox.reference, calendar: calendar)
                == .day("2026-10-26")
        )
    }

    @Test(
        "Calendars other than the Gregorian one count the same weeks",
        arguments: [
            Calendar.Identifier.iso8601, .buddhist, .japanese, .hebrew, .islamicUmmAlQura,
            .persian, .chinese, .indian,
        ])
    func otherCalendars(identifier: Calendar.Identifier) {
        for text in awkwardDates + ["2026-10-30"] {
            let date = GarminDate.day(text)
            for firstWeekday in [1, 2, 7] {
                let gregorian = AnalyticsBlackBox.calendar(firstWeekday: firstWeekday)
                let other = AnalyticsBlackBox.calendar(
                    firstWeekday: firstWeekday, zone: "Europe/Berlin", identifier: identifier)
                #expect(
                    TrainingWeek.weekStart(of: date, calendar: other)
                        == TrainingWeek.weekStart(of: date, calendar: gregorian),
                    "\(text), first weekday \(firstWeekday)")
            }
        }
    }
}

/// Documented behavior that the black-box tests found missing, kept so that it stays fixed.
@Suite("Training weeks: regressions")
struct TrainingWeekBlackBoxRegressions {
    @Test("The first day of the week does not depend on the time zone", arguments: zones)
    func timeZones(zone: String) {
        for text in awkwardDates {
            let date = GarminDate.day(text)
            for firstWeekday in 1...7 {
                let reference = AnalyticsBlackBox.calendar(firstWeekday: firstWeekday)
                let local = AnalyticsBlackBox.calendar(firstWeekday: firstWeekday, zone: zone)
                #expect(
                    TrainingWeek.weekStart(of: date, calendar: local)
                        == TrainingWeek.weekStart(of: date, calendar: reference),
                    "\(text), first weekday \(firstWeekday), \(zone)")
            }
        }
    }

    @Test("Random dates: the start is the latest first weekday on or before the date")
    func randomDates() {
        var random = BlackBoxRandom(seed: 42)
        let origin = GarminDate.day("1990-01-01")
        for _ in 0..<400 {
            let date = origin.adding(days: random.integer(0...20_000))
            let firstWeekday = random.integer(1...7)
            let zone = zones[random.integer(0...(zones.count - 1))]
            let calendar = AnalyticsBlackBox.calendar(firstWeekday: firstWeekday, zone: zone)
            let start = TrainingWeek.weekStart(of: date, calendar: calendar)
            let inputs = Comment(rawValue: "\(date), first weekday \(firstWeekday), \(zone)")
            #expect(start <= date, inputs)
            #expect(start.days(to: date) < 7, inputs)
            #expect(AnalyticsBlackBox.weekday(of: start) == firstWeekday, inputs)
            #expect(TrainingWeek.weekStart(of: start, calendar: calendar) == start, inputs)
        }
    }
}

@Suite("Training weeks: totals")
struct BlackBoxTrainingWeekTests {
    private let mondays = AnalyticsBlackBox.calendar(firstWeekday: 2)

    @Test("The weeks up to the one containing the last day, oldest first", arguments: [1, 2, 12])
    func weekRange(count: Int) {
        let weeks = TrainingWeek.weeks(
            [], through: AnalyticsBlackBox.reference, count: count, calendar: mondays)
        let lastStart = GarminDate.day("2026-10-26")
        #expect(
            weeks.map(\.start) == (0..<count).map { lastStart.adding(days: 7 * ($0 - count + 1)) })
        #expect(weeks.map(\.id) == weeks.map(\.start))
        for week in weeks {
            #expect(week.activityCount == 0)
            #expect(week.load == 0)
            #expect(week.total == 0)
            #expect(week.seconds.values.allSatisfy { $0 == 0 })
        }
    }

    @Test("No weeks asked for, none returned")
    func noWeeks() {
        #expect(
            TrainingWeek.weeks(
                [], through: AnalyticsBlackBox.reference, count: 0, calendar: mondays
            ).isEmpty
        )
    }

    @Test("Seconds per sport, activities and load of each week")
    func totals() throws {
        let workouts = [
            try AnalyticsBlackBox.workout(id: 1, on: .day("2026-10-26"), load: 80, duration: 3600),
            try AnalyticsBlackBox.workout(
                id: 2, on: .day("2026-10-27"), load: 120, typeKey: "road_biking", duration: 5400),
            try AnalyticsBlackBox.workout(id: 3, on: .day("2026-10-30"), load: 60, duration: 1800),
            try AnalyticsBlackBox.workout(
                id: 4, on: .day("2026-10-28"), load: nil, typeKey: "strength_training",
                duration: 2700),
            try AnalyticsBlackBox.workout(id: 5, on: .day("2026-10-25"), load: 40, duration: 1200),
            try AnalyticsBlackBox.workout(id: 6, on: .day("2026-10-19"), load: 30, duration: 900),
        ]
        let weeks = TrainingWeek.weeks(
            workouts, through: AnalyticsBlackBox.reference, count: 2, calendar: mondays)
        let last = try #require(weeks.last)
        let first = try #require(weeks.first)
        #expect(last.start == .day("2026-10-26"))
        #expect(last.activityCount == 4)
        #expect(last.load == 260)
        #expect(last.seconds[.running] == 5400)
        #expect(last.seconds[.cycling] == 5400)
        #expect(last.seconds[.strength] == 2700)
        #expect((last.seconds[.swimming] ?? 0) == 0)
        #expect(last.total == 13_500)
        #expect(first.start == .day("2026-10-19"))
        #expect(first.activityCount == 2)
        #expect(first.load == 70)
        #expect(first.seconds[.running] == 2100)
        #expect(first.total == 2100)
    }

    @Test("Sunday's activity belongs to the week that the calendar says")
    func firstWeekdayDecides() throws {
        let sunday = try AnalyticsBlackBox.workout(id: 1, on: .day("2026-10-25"), load: 50)
        let sundays = AnalyticsBlackBox.calendar(firstWeekday: 1)
        let byMonday = TrainingWeek.weeks(
            [sunday], through: AnalyticsBlackBox.reference, count: 2, calendar: mondays)
        let bySunday = TrainingWeek.weeks(
            [sunday], through: AnalyticsBlackBox.reference, count: 2, calendar: sundays)
        #expect(byMonday.map(\.activityCount) == [1, 0])
        #expect(bySunday.map(\.activityCount) == [0, 1])
        #expect(bySunday.map(\.start) == [.day("2026-10-18"), .day("2026-10-25")])
    }

    @Test("Activities before the first week are left out")
    func olderActivitiesIgnored() throws {
        let old = try AnalyticsBlackBox.workout(id: 1, on: .day("2026-10-18"), load: 50)
        let weeks = TrainingWeek.weeks(
            [old], through: AnalyticsBlackBox.reference, count: 2, calendar: mondays)
        #expect(weeks.map(\.activityCount) == [0, 0])
        #expect(weeks.map(\.load) == [0, 0])
    }

    @Test("Random activities: every one is counted once, in its own week")
    func randomTotals() throws {
        var random = BlackBoxRandom(seed: 99)
        let types = ["running", "cycling", "lap_swimming", "walking", "strength_training", "yoga"]
        let first = GarminDate.day("2026-08-10")
        var workouts: [Workout] = []
        for id in 1...150 {
            let date = first.adding(days: random.integer(0...81))
            workouts.append(
                try AnalyticsBlackBox.workout(
                    id: id, on: date, load: random.uniform(0...200).rounded(),
                    typeKey: types[random.integer(0...(types.count - 1))],
                    duration: random.uniform(600...7200).rounded()))
        }
        for firstWeekday in 1...7 {
            let calendar = AnalyticsBlackBox.calendar(
                firstWeekday: firstWeekday, zone: "Europe/Berlin")
            let weeks = TrainingWeek.weeks(
                workouts, through: AnalyticsBlackBox.reference, count: 14, calendar: calendar)
            #expect(weeks.count == 14)
            for week in weeks {
                let members = workouts.filter {
                    week.start <= $0.date && $0.date < week.start.adding(days: 7)
                }
                #expect(week.activityCount == members.count)
                #expect(
                    AnalyticsBlackBox.isClose(
                        week.load, members.compactMap(\.trainingLoad).reduce(0, +)))
                #expect(AnalyticsBlackBox.isClose(week.total, members.map(\.duration).reduce(0, +)))
                #expect(AnalyticsBlackBox.isClose(week.total, week.seconds.values.reduce(0, +)))
                for sport in Sport.allCases {
                    let seconds = members.filter { $0.sport == sport }.map(\.duration)
                    #expect(
                        AnalyticsBlackBox.isClose(week.seconds[sport] ?? 0, seconds.reduce(0, +)))
                }
            }
        }
    }
}

@Suite("Heart rate zone sets")
struct BlackBoxHeartRateZoneSetTests {
    @Test("The floors of zones 1 to 5 and the maximum")
    func floors() throws {
        let set = try #require(HeartRateZoneSet(AnalyticsBlackBox.zones("RUNNING")))
        #expect(set.floors == [100, 120, 140, 160, 175])
        #expect(set.maximum == 190)
    }

    @Test("Zones without a maximum still have floors")
    func noMaximum() throws {
        let set = try #require(HeartRateZoneSet(AnalyticsBlackBox.zones("DEFAULT", maximum: nil)))
        #expect(set.floors == [100, 120, 140, 160, 175])
        #expect(set.maximum == nil)
    }

    @Test("Zones without floors are no zones")
    func noFloors() {
        #expect(HeartRateZoneSet(AnalyticsBlackBox.zones("RUNNING", floors: [])) == nil)
    }

    @Test("Labels: the zone's range in beats per minute", arguments: 0..<5)
    func labels(index: Int) throws {
        let set = try #require(HeartRateZoneSet(AnalyticsBlackBox.zones("RUNNING")))
        let label = set.label(zone: index)
        #expect(label.hasPrefix("\(set.floors[index])"))
        #expect(label.hasSuffix("bpm"))
        if index < 4 {
            let next = set.floors[index + 1]
            #expect(label.contains("\(next - 1)") || label.contains("\(next)"))
            #expect(label.contains("–"))
        }
    }
}
