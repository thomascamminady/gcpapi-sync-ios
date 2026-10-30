import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// The distinct date windows of the activity searches among `requests`, in order.
private func windows(_ requests: [HTTPRequest]) -> [ClosedRange<GarminDate>] {
    var result: Set<ClosedRange<GarminDate>> = []
    for request in requests where AnalyticsBlackBox.isSearch(request) {
        let query = AnalyticsBlackBox.query(request)
        if let first = query["startDate"].flatMap({ try? GarminDate($0) }),
            let last = query["endDate"].flatMap({ try? GarminDate($0) }), first <= last
        {
            result.insert(first...last)
        }
    }
    return result.sorted { $0.lowerBound < $1.lowerBound }
}

/// Whether `windows` cover `first...last` exactly, without gaps or overlaps, each at most
/// `TrainingLoader.windowDays` long.
private func expectTiling(
    _ windows: [ClosedRange<GarminDate>], first: GarminDate, last: GarminDate
) {
    #expect(windows.first?.lowerBound == first)
    #expect(windows.last?.upperBound == last)
    for (window, next) in zip(windows, windows.dropFirst()) {
        #expect(window.upperBound.adding(days: 1) == next.lowerBound, "\(window) then \(next)")
    }
    for window in windows {
        #expect(window.lowerBound.days(to: window.upperBound) < TrainingLoader.windowDays)
    }
}

/// One activity a day, with an id from its date.
nonisolated private func daily(_ date: GarminDate) -> [Int] {
    [GarminDate.day("2020-01-01").days(to: date) + 1]
}

@Suite("Training loader: fetching activities in windows")
struct BlackBoxActivityWindowTests {
    @Test("Documented limits")
    func limits() {
        #expect(TrainingLoader.windowDays >= 1)
        #expect(TrainingLoader.concurrentWindows >= 1)
        #expect(TrainingLoader.shownDays >= 1)
        #expect(TrainingLoader.warmUpDays >= 1)
        #expect(TrainingLoader.shownWeeks >= 1)
    }

    @Test(
        "The windows cover the range exactly, and every activity comes back once",
        arguments: [1, 2, 13, 14, 15, 28, 29, 45, 100, 210])
    func windowsTileTheRange(days: Int) async throws {
        let first = GarminDate.day("2026-04-03")
        let last = first.adding(days: days - 1)
        let responder = BlackBoxSearchResponder(activities: daily)
        let stub = StubTransport { responder.respond($0) }
        let activities = try await TrainingLoader.activities(
            from: try AnalyticsBlackBox.client(of: stub), first: first, last: last)
        let requests = await stub.requests
        expectTiling(windows(requests), first: first, last: last)
        let ids = activities.map(\.activityId)
        #expect(ids.count == Set(ids).count)
        #expect(Set(ids) == Set(AnalyticsBlackBox.dates(from: first, count: days).flatMap(daily)))
        for request in requests where AnalyticsBlackBox.isSearch(request) {
            let limit = AnalyticsBlackBox.query(request)["limit"].flatMap { Int($0) } ?? 0
            #expect((1...45).contains(limit))
        }
    }

    @Test("A busy window is paged until every activity is fetched")
    func paging() async throws {
        let first = GarminDate.day("2026-06-01")
        let busy = first.adding(days: 3)
        let responder = BlackBoxSearchResponder { date in
            date == busy ? Array(1000...1119) : daily(date)
        }
        let stub = StubTransport { responder.respond($0) }
        let activities = try await TrainingLoader.activities(
            from: try AnalyticsBlackBox.client(of: stub), first: first, last: first.adding(days: 30)
        )
        let ids = activities.map(\.activityId)
        #expect(ids.count == Set(ids).count)
        #expect(Set(1000...1119).isSubset(of: Set(ids)))
        #expect(ids.count == 120 + 30)
    }

    @Test("Activities come back as Garmin sent them")
    func contents() async throws {
        let day = GarminDate.day("2026-06-10")
        let responder = BlackBoxSearchResponder { $0 == day ? [77] : [] }
        let stub = StubTransport { responder.respond($0) }
        let activities = try await TrainingLoader.activities(
            from: try AnalyticsBlackBox.client(of: stub), first: day.adding(days: -20), last: day)
        let activity = try #require(activities.first)
        #expect(activities.count == 1)
        #expect(activity.activityId == 77)
        #expect(activity.startTimeLocal?.date == day)
        #expect(activity.activityTrainingLoad == 50)
        #expect(activity.activityType?.typeKey == "running")
    }

    @Test("A failing window fails the whole fetch")
    func failure() async throws {
        let first = GarminDate.day("2026-01-01")
        var responder = BlackBoxSearchResponder(activities: daily)
        responder.failing = first.adding(days: 40)
        let stub = StubTransport { [responder] in responder.respond($0) }
        let client = try AnalyticsBlackBox.client(of: stub)
        await #expect(throws: (any Error).self) {
            try await TrainingLoader.activities(
                from: client, first: first, last: first.adding(days: 99))
        }
    }

    @Test("Windows are fetched a few at a time, never more than the limit")
    func concurrency() async throws {
        let gauge = BlackBoxFlightGauge()
        let transport = BlackBoxSlowTransport(
            gauge: gauge, responder: BlackBoxSearchResponder(activities: daily))
        let first = GarminDate.day("2026-01-01")
        let days = TrainingLoader.windowDays * (TrainingLoader.concurrentWindows * 3 + 1)
        let activities = try await TrainingLoader.activities(
            from: try AnalyticsBlackBox.client(of: transport), first: first,
            last: first.adding(days: days - 1))
        #expect(activities.count == days)
        let maximum = await gauge.maximum
        #expect(maximum <= TrainingLoader.concurrentWindows)
        if TrainingLoader.concurrentWindows > 1 {
            #expect(maximum > 1)
        }
    }

    @Test("Loading asks for the days shown and their warm-up, ending on the given day")
    func loadRange() async throws {
        let end = AnalyticsBlackBox.reference
        let responder = BlackBoxSearchResponder(
            activities: daily,
            zones: """
                [{"zone1Floor":100,"zone2Floor":120,"zone3Floor":140,"zone4Floor":160,\
                "zone5Floor":175,"maxHeartRateUsed":190,"sport":"RUNNING"}]
                """)
        let stub = StubTransport { responder.respond($0) }
        var analysis = AnalysisSettings()
        analysis.fitnessDays = 30
        analysis.fatigueDays = 5
        let data = try await TrainingLoader.load(
            from: try AnalyticsBlackBox.client(of: stub), endingOn: end, analysis: analysis)
        let total = TrainingLoader.shownDays + TrainingLoader.warmUpDays
        let first = end.adding(days: 1 - total)
        expectTiling(windows(await stub.requests), first: first, last: end)
        #expect(data.loadHistory.map(\.date) == AnalyticsBlackBox.dates(from: first, count: total))
        #expect(data.loadHistory.allSatisfy { $0.load == 50 })
        #expect(data.zones["RUNNING"]?.floors == [100, 120, 140, 160, 175])
        let workouts = AnalyticsBlackBox.dates(from: first, count: total).flatMap { date in
            daily(date).compactMap {
                Workout(AnalyticsBlackBox.activity(id: $0, on: date, load: 50))
            }
        }
        let expected = TrainingLoad.days(
            workouts, from: first, through: end, fitnessDays: 30, fatigueDays: 5)
        for (day, other) in zip(data.loadHistory, expected) {
            #expect(AnalyticsBlackBox.isClose(day.fitness, other.fitness))
            #expect(AnalyticsBlackBox.isClose(day.fatigue, other.fatigue))
        }
    }
}

@Suite("Training loader: assembling training data")
struct BlackBoxTrainingAssembleTests {
    private let mondays = AnalyticsBlackBox.calendar(firstWeekday: 2, zone: "Europe/Berlin")
    private let end = AnalyticsBlackBox.reference

    private var first: GarminDate {
        end.adding(days: 1 - TrainingLoader.shownDays - TrainingLoader.warmUpDays)
    }

    private func assemble(
        _ activities: [SummarizedActivity], zones: [HeartRateZones] = [],
        analysis: AnalysisSettings = AnalysisSettings()
    ) -> TrainingData {
        TrainingLoader.assemble(
            activities: activities, zones: zones, endingOn: end, calendar: mondays,
            analysis: analysis)
    }

    @Test("Load history: warm-up and shown days, oldest first, ending on the last day")
    func shape() {
        let data = assemble([])
        let total = TrainingLoader.shownDays + TrainingLoader.warmUpDays
        #expect(data.loadHistory.map(\.date) == AnalyticsBlackBox.dates(from: first, count: total))
        #expect(data.load == Array(data.loadHistory.suffix(TrainingLoader.shownDays)))
        #expect(data.load.first?.date == end.adding(days: 1 - TrainingLoader.shownDays))
        #expect(data.workouts.isEmpty)
        #expect(data.weeks.count == TrainingLoader.shownWeeks)
        #expect(data.weeks.last?.start == TrainingWeek.weekStart(of: end, calendar: mondays))
        #expect(data.zones.isEmpty)
    }

    @Test("An activity seen twice counts once")
    func deduplication() throws {
        let day = end.adding(days: -3)
        let activity = AnalyticsBlackBox.activity(id: 7, on: day, load: 90)
        let data = assemble([
            activity, activity, AnalyticsBlackBox.activity(id: 8, on: day, load: 10),
        ])
        #expect(data.workouts.map(\.id).sorted() == [7, 8])
        let loaded = try #require(data.loadHistory.first { $0.date == day })
        #expect(loaded.load == 100)
        #expect(data.weeks.last?.activityCount == 2)
    }

    @Test("Workouts are newest first, whatever order Garmin sends")
    func sorting() {
        var random = BlackBoxRandom(seed: 8)
        var activities: [SummarizedActivity] = []
        for id in 1...60 {
            let date = end.adding(days: -random.integer(0...(TrainingLoader.shownDays - 1)))
            activities.append(
                AnalyticsBlackBox.activity(id: id, on: date, hour: random.integer(5...20), load: 40)
            )
        }
        activities.shuffle(using: &random)
        let workouts = assemble(activities).workouts
        #expect(workouts.count == 60)
        for (newer, older) in zip(workouts, workouts.dropFirst()) {
            #expect(newer.date >= older.date)
            if let newerStart = newer.start, let olderStart = older.start {
                #expect(newerStart >= olderStart)
            }
        }
    }

    @Test("Activities without a start or a duration are left out")
    func incomplete() {
        let day = end.adding(days: -2)
        let complete = AnalyticsBlackBox.activity(id: 1, on: day, load: 30)
        let noStart = SummarizedActivity(activityId: 2, duration: 1800, activityTrainingLoad: 40)
        let noDuration = AnalyticsBlackBox.activity(id: 3, on: day, duration: nil, load: 50)
        let data = assemble([complete, noStart, noDuration])
        #expect(data.workouts.map(\.id) == [1])
        #expect(data.loadHistory.map(\.load).reduce(0, +) == 30)
    }

    @Test("Warm-up activities build fitness before the first day shown")
    func warmUp() throws {
        let warmUpDay = first.adding(days: TrainingLoader.warmUpDays / 2)
        let data = assemble([AnalyticsBlackBox.activity(id: 1, on: warmUpDay, load: 300)])
        let shownFirst = try #require(data.load.first)
        #expect(shownFirst.fitness > 0)
        #expect(data.loadHistory.first { $0.date == warmUpDay }?.load == 300)
        #expect(data.load.allSatisfy { $0.load == 0 })
    }

    @Test(
        "The history equals the days of the analysis' windows",
        arguments: [(42.0, 7.0), (21.0, 3.0)])
    func analysisWindows(fitnessDays: Double, fatigueDays: Double) {
        var random = BlackBoxRandom(seed: 31)
        let total = TrainingLoader.shownDays + TrainingLoader.warmUpDays
        let activities = (1...120).map { id in
            AnalyticsBlackBox.activity(
                id: id, on: first.adding(days: random.integer(0...(total - 1))),
                load: random.uniform(5...250).rounded())
        }
        var analysis = AnalysisSettings()
        analysis.fitnessDays = fitnessDays
        analysis.fatigueDays = fatigueDays
        let data = assemble(activities, analysis: analysis)
        let expected = TrainingLoad.days(
            activities.compactMap(Workout.init), from: first, through: end,
            fitnessDays: fitnessDays, fatigueDays: fatigueDays)
        #expect(data.loadHistory.count == expected.count)
        for (day, other) in zip(data.loadHistory, expected) {
            #expect(day.date == other.date)
            #expect(AnalyticsBlackBox.isClose(day.load, other.load))
            #expect(AnalyticsBlackBox.isClose(day.fitness, other.fitness))
            #expect(AnalyticsBlackBox.isClose(day.fatigue, other.fatigue))
        }
    }

    @Test("Weeks are the calendar's weeks of the workouts")
    func weeks() {
        var random = BlackBoxRandom(seed: 12)
        let activities = (1...80).map { id in
            AnalyticsBlackBox.activity(
                id: id, on: end.adding(days: -random.integer(0...83)),
                typeKey: ["running", "cycling", "walking"][random.integer(0...2)],
                duration: random.uniform(900...5400).rounded(), load: 60)
        }
        for calendar in [
            mondays, AnalyticsBlackBox.calendar(firstWeekday: 1, zone: "America/New_York"),
        ] {
            let data = TrainingLoader.assemble(
                activities: activities, zones: [], endingOn: end, calendar: calendar)
            let expected = TrainingWeek.weeks(
                activities.compactMap(Workout.init), through: end,
                count: TrainingLoader.shownWeeks, calendar: calendar)
            #expect(data.weeks == expected)
        }
    }

    @Test("Zones by Garmin's sport name")
    func zones() {
        let data = assemble(
            [],
            zones: [
                AnalyticsBlackBox.zones("RUNNING"),
                AnalyticsBlackBox.zones("DEFAULT", floors: [90, 110, 130, 150, 170], maximum: 185),
                AnalyticsBlackBox.zones("CYCLING", floors: []),
            ])
        #expect(data.zones["RUNNING"]?.floors == [100, 120, 140, 160, 175])
        #expect(data.zones["DEFAULT"]?.maximum == 185)
        #expect(data.zones["CYCLING"] == nil)
        #expect(data.heartRateZones(for: .running)?.floors == [100, 120, 140, 160, 175])
        #expect(data.heartRateZones(for: .cycling)?.floors == [90, 110, 130, 150, 170])
    }
}

@Suite("Training data")
struct BlackBoxTrainingDataTests {
    private let running = HeartRateZoneSet(AnalyticsBlackBox.zones("RUNNING"))
    private let cycling = HeartRateZoneSet(
        AnalyticsBlackBox.zones("CYCLING", floors: [95, 115, 135, 155, 165]))
    private let swimming = HeartRateZoneSet(
        AnalyticsBlackBox.zones("SWIMMING", floors: [80, 100, 120, 140, 150]))
    private let fallback = HeartRateZoneSet(
        AnalyticsBlackBox.zones("DEFAULT", floors: [90, 110, 130, 150, 170]))

    private func data(_ zones: [String: HeartRateZoneSet?]) -> TrainingData {
        TrainingData(
            workouts: [], history: [], loadHistory: [], weeks: [],
            zones: zones.compactMapValues { $0 })
    }

    @Test("Each sport uses its own zones")
    func ownZones() {
        let data = data(
            ["RUNNING": running, "CYCLING": cycling, "SWIMMING": swimming, "DEFAULT": fallback])
        #expect(data.heartRateZones(for: .running) == running)
        #expect(data.heartRateZones(for: .cycling) == cycling)
        #expect(data.heartRateZones(for: .swimming) == swimming)
        #expect(data.heartRateZones(for: .strength) == fallback)
        #expect(data.heartRateZones(for: .other) == fallback)
        #expect(data.heartRateZones(for: .walking) != nil)
    }

    @Test("Sports without zones of their own use the default ones")
    func defaultZones() {
        let data = data(["DEFAULT": fallback])
        for sport in Sport.allCases {
            #expect(data.heartRateZones(for: sport) == fallback)
        }
    }

    @Test("Without zones there are none")
    func noZones() {
        let data = data([:])
        for sport in Sport.allCases {
            #expect(data.heartRateZones(for: sport) == nil)
        }
    }

    @Test("The days shown are the last of the history", arguments: [0, 1, 5, 400])
    func shownDays(extra: Int) {
        let count = TrainingLoader.shownDays + extra
        let history = AnalyticsBlackBox.dates(from: .day("2025-01-01"), count: count).map {
            TrainingLoad.Day(date: $0, load: 1, fitness: 2, fatigue: 3)
        }
        let data = TrainingData(
            workouts: [], history: [], loadHistory: history, weeks: [], zones: [:])
        #expect(data.load == Array(history.suffix(TrainingLoader.shownDays)))
    }

    @Test("A history shorter than the days shown is shown whole")
    func shortHistory() {
        let history = AnalyticsBlackBox.dates(from: .day("2025-01-01"), count: 10).map {
            TrainingLoad.Day(date: $0, load: 1, fitness: 2, fatigue: 3)
        }
        let data = TrainingData(
            workouts: [], history: [], loadHistory: history, weeks: [], zones: [:])
        #expect(data.load == history)
    }
}
