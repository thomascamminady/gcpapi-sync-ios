import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A Monday-first calendar in UTC, so week boundaries do not depend on the test machine.
private let mondayFirst: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.firstWeekday = 2
    calendar.timeZone = .gmt
    return calendar
}()

/// An activity on `date` with only what a test needs.
private func activity(
    _ id: Int, on date: GarminDate, type: String = "running", minutes: Double = 30,
    load: Double? = 50
) -> SummarizedActivity {
    SummarizedActivity(
        activityId: id,
        startTimeLocal: (try? GarminTime(hour: 7)).map { LocalDateTime(date: date, time: $0) },
        activityType: ActivityType(typeKey: type),
        duration: minutes * 60,
        activityTrainingLoad: load
    )
}

private func workout(
    _ id: Int, on date: GarminDate, type: String = "running", minutes: Double = 30,
    load: Double? = 50
) throws -> Workout {
    try #require(Workout(activity(id, on: date, type: type, minutes: minutes, load: load)))
}

@Suite struct SportTests {
    @Test(
        arguments: [
            ("running", Sport.running), ("treadmill_running", .running),
            ("trail_running", .running),
            ("road_biking", .cycling), ("indoor_cycling", .cycling), ("virtual_ride", .cycling),
            ("lap_swimming", .swimming), ("open_water_swimming", .swimming),
            ("strength_training", .strength), ("hiking", .walking), ("walking", .walking),
            ("indoor_rowing", .other), ("hiit", .other),
        ] as [(String, Sport)])
    func garminTypesAreGrouped(typeKey: String, sport: Sport) {
        #expect(Sport(typeKey: typeKey) == sport)
    }

    @Test(arguments: Sport.allCases)
    func everySportIsPresentable(sport: Sport) {
        #expect(!sport.title.isEmpty)
        #expect(!sport.symbol.isEmpty)
        _ = sport.color
    }

    @Test func missingTypesAreOther() {
        #expect(Sport(typeKey: nil) == .other)
    }
}

@Suite struct WorkoutTests {
    private let day = GarminDate.day("2026-10-27")

    @Test func mapsGarminsActivity() throws {
        let source = SummarizedActivity(
            activityId: 7, activityName: "Tempo",
            startTimeLocal: activity(1, on: day).startTimeLocal,
            activityType: ActivityType(typeKey: "trail_running"), distance: 10_000, duration: 3000,
            elevationGain: 120, averageSpeed: 3.33, calories: 600, averageHR: 150, maxHR: 171,
            averageRunningCadenceInStepsPerMinute: 174, aerobicTrainingEffect: 3.4,
            anaerobicTrainingEffect: 1.2, locationName: "Hills", trainingEffectLabel: "TEMPO",
            activityTrainingLoad: 140, aerobicTrainingEffectMessage: "IMPROVING_TEMPO_3",
            hrTimeInZone1: 60, hrTimeInZone2: 600, hrTimeInZone3: 1500, hrTimeInZone4: 840)
        let workout = try #require(Workout(source))
        #expect(workout.id == 7)
        #expect(workout.name == "Tempo")
        #expect(workout.sport == .running)
        #expect(workout.date == day)
        #expect(workout.distance == 10_000)
        #expect(workout.cadence == 174)
        #expect(workout.trainingLoad == 140)
        #expect(workout.primaryBenefit == "TEMPO")
        #expect(workout.heartRateZones == [60, 600, 1500, 840, 0])
        #expect(workout.powerZones.isEmpty)
        #expect(workout.location == "Hills")
        // Without a UTC start, the local start time is used.
        #expect(workout.start == day.startOfDay(in: .current).addingTimeInterval(7 * 3600))
    }

    @Test func fillsGapsAndSkipsUndatedActivities() throws {
        var source = activity(3, on: day, type: "strength_training")
        source.activityName = ""
        source.distance = 0
        let workout = try #require(Workout(source))
        #expect(workout.name == Sport.strength.title)
        #expect(workout.distance == nil)
        #expect(workout.heartRateZones.isEmpty)
        var undated = activity(4, on: day)
        undated.startTimeLocal = nil
        #expect(Workout(undated) == nil)
        var untimed = activity(5, on: day)
        untimed.duration = nil
        #expect(Workout(untimed) == nil)
    }
}

@Suite struct TrainingLoadTests {
    private let first = GarminDate.day("2026-10-01")

    @Test func fitnessAndFatigueAreExponentialAverages() throws {
        let days = TrainingLoad.days(
            [try workout(1, on: first, load: 42), try workout(2, on: first, load: nil)],
            from: first, through: first.adding(days: 1))
        #expect(days.count == 2)
        #expect(days[0].load == 42)
        #expect(days[0].fitness == 1)
        #expect(days[0].fatigue == 6)
        #expect(days[0].form == -5)
        #expect(days[0].formShare == -5)
        #expect(days[0].zone == .overreaching)
        #expect(abs(days[1].fitness - 41.0 / 42) < 1e-12)
        #expect(abs(days[1].fatigue - 36.0 / 7) < 1e-12)
        #expect(TrainingLoad.days([], from: first, through: first)[0].formShare == nil)
    }

    @Test(
        arguments: [
            (0.3, FormZone.detraining), (0.2, .detraining), (0.1, .fresh), (0.05, .fresh),
            (0.0, .neutral), (-0.1, .neutral), (-0.2, .productive), (-0.3, .productive),
            (-0.31, .overreaching),
        ] as [(Double, FormZone)])
    func formZones(share: Double, zone: FormZone) {
        #expect(FormZone(share: share) == zone)
    }

    @Test(arguments: FormZone.allCases)
    func everyZoneIsExplained(zone: FormZone) {
        #expect(!zone.title.isEmpty)
        #expect(!zone.symbol.isEmpty)
        #expect(!zone.explanation.isEmpty)
        #expect(zone.band.contains((zone.band.lowerBound + zone.band.upperBound) / 2))
    }
}

@Suite struct TrainingDataTests {
    private let thursday = GarminDate.day("2026-10-29")

    @Test func weeksStartOnTheCalendarsFirstDay() {
        #expect(TrainingWeek.weekStart(of: thursday, calendar: mondayFirst) == .day("2026-10-26"))
        var sundayFirst = mondayFirst
        sundayFirst.firstWeekday = 1
        #expect(TrainingWeek.weekStart(of: thursday, calendar: sundayFirst) == .day("2026-10-25"))
        #expect(
            TrainingWeek.weekStart(of: .day("2026-10-26"), calendar: mondayFirst)
                == .day("2026-10-26"))
    }

    @Test func weeksAddUpBySport() throws {
        let workouts = [
            try workout(1, on: .day("2026-10-26"), minutes: 60, load: 80),
            try workout(2, on: .day("2026-10-28"), type: "road_biking", minutes: 90, load: 100),
            try workout(3, on: .day("2026-10-20"), minutes: 30, load: nil),
        ]
        let weeks = TrainingWeek.weeks(workouts, through: thursday, count: 3, calendar: mondayFirst)
        #expect(weeks.map(\.start) == [.day("2026-10-12"), .day("2026-10-19"), .day("2026-10-26")])
        #expect(weeks[0].activityCount == 0)
        #expect(weeks[1].seconds == [.running: 1800])
        #expect(weeks[1].load == 0)
        #expect(weeks[2].seconds == [.running: 3600, .cycling: 5400])
        #expect(weeks[2].total == 9000)
        #expect(weeks[2].activityCount == 2)
        #expect(weeks[2].load == 180)
    }

    @Test func heartRateZonesBySport() throws {
        let running = HeartRateZones(
            zone1Floor: 95, zone2Floor: 114, zone3Floor: 133, zone4Floor: 152, zone5Floor: 171,
            maxHeartRateUsed: 190, sport: "RUNNING")
        let fallback = HeartRateZones(
            zone1Floor: 90, zone2Floor: 110, zone3Floor: 130, zone4Floor: 150, zone5Floor: 170,
            sport: "DEFAULT")
        #expect(HeartRateZoneSet(HeartRateZones(zone1Floor: 90, sport: "CYCLING")) == nil)
        let data = TrainingLoader.assemble(
            activities: [], zones: [running, fallback], endingOn: thursday, calendar: mondayFirst)
        let runningZones = try #require(data.heartRateZones(for: .running))
        #expect(runningZones.label(zone: 0) == "95–113 bpm")
        #expect(runningZones.label(zone: 4) == "171–190 bpm")
        let cyclingZones = try #require(data.heartRateZones(for: .cycling))
        #expect(cyclingZones.label(zone: 4) == "170+ bpm")
        #expect(data.heartRateZones(for: .swimming) == cyclingZones)
    }

    @Test func assembleKeepsTheShownRangeNewestFirst() throws {
        let old = thursday.adding(days: -100)
        let data = TrainingLoader.assemble(
            activities: [
                activity(1, on: thursday.adding(days: -3)), activity(2, on: thursday),
                activity(2, on: thursday), activity(3, on: old, load: 420),
            ],
            zones: [], endingOn: thursday, calendar: mondayFirst)
        #expect(data.workouts.map(\.id) == [2, 1])
        #expect(data.load.count == TrainingLoader.shownDays)
        #expect(data.load.first?.date == thursday.adding(days: 1 - TrainingLoader.shownDays))
        // The activity before the shown range still built fitness.
        #expect(try #require(data.load.first).fitness > 0)
        #expect(data.weeks.count == TrainingLoader.shownWeeks)
    }

    @Test func activitiesAreFetchedInWindows() async throws {
        let transport = StubTransport { request in
            request.path == tokenPath ? (200, "token") : (200, "[]")
        }
        let first = GarminDate.day("2026-10-01")
        _ = try await TrainingLoader.activities(
            from: try client(transport), first: first, last: first.adding(days: 29))
        let windows = await transport.requests.filter { $0.path != tokenPath }
            .compactMap { request in
                request.query["startDate"].flatMap { start in
                    request.query["endDate"].map { "\(start)/\($0)" }
                }
            }
            .sorted()
        #expect(
            windows == [
                "2026-10-01/2026-10-14", "2026-10-15/2026-10-28", "2026-10-29/2026-10-30",
            ])
    }

    @Test func loadsTheDemoThroughGarminsJSON() async throws {
        let data = try await TrainingLoader.load(
            from: try client(DemoTransport()), endingOn: thursday)
        #expect(data == TrainingData.sample(endingOn: thursday))
        #expect(Set(data.workouts.map(\.sport)) == [.running, .strength, .cycling])
        #expect(data.workouts.allSatisfy { $0.trainingLoad != nil })
        #expect(data.heartRateZones(for: .running) != nil)
    }
}

/// Hands out queued results and counts the loads.
private actor TrainingResults {
    var queue: [Result<TrainingData, Problem>]
    var count = 0

    init(_ queue: [Result<TrainingData, Problem>]) {
        self.queue = queue
    }

    func next() throws -> TrainingData {
        count += 1
        return try queue.removeFirst().get()
    }
}

/// A clock that tests move forward.
private final class Clock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@Suite struct TrainingModelTests {
    private let end = GarminDate.day("2026-10-29")

    @Test func loadsAndKeepsDataWhenARefreshFails() async {
        let sample = TrainingData.sample(endingOn: end)
        let results = TrainingResults([.success(sample), .failure(.offline), .success(sample)])
        let model = TrainingModel(today: { end }, fetch: { _ in try await results.next() })
        #expect(model.phase == .loading)
        await model.load()
        #expect(model.phase == .loaded(sample))
        #expect(model.lastUpdated != nil)
        await model.load()
        #expect(model.phase == .loaded(sample))
        #expect(model.refreshProblem == .offline)
        await model.load()
        #expect(model.refreshProblem == nil)
    }

    @Test func aFirstFailureIsShownInPlace() async {
        let model = TrainingModel { _ in throw Problem.rateLimited }
        await model.load()
        #expect(model.phase == .failed(.rateLimited))
        let cancelled = TrainingModel { _ in throw CancellationError() }
        await cancelled.load()
        #expect(cancelled.phase == .loading)
    }

    @Test func recentDataIsNotFetchedAgain() async {
        let clock = Clock()
        let results = TrainingResults([
            .success(.sample(endingOn: end)), .success(.sample(endingOn: end)),
        ])
        let model = TrainingModel(
            today: { end }, now: { clock.now }, fetch: { _ in try await results.next() })
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(await results.count == 1)
        clock.now += 16 * 60
        await model.loadIfNeeded()
        #expect(await results.count == 2)
    }

    @Test func healthIsNotFetchedAgainWhenSwitchingTabs() async {
        let clock = Clock()
        let model = HealthModel(
            today: { end }, now: { clock.now },
            fetch: { end, days in .sample(endingOn: end, days: days) })
        await model.loadIfNeeded()
        let first = model.lastUpdated
        clock.now += 60
        await model.loadIfNeeded()
        #expect(model.lastUpdated == first)
        clock.now += 15 * 60
        await model.loadIfNeeded()
        #expect(model.lastUpdated == clock.now)
    }
}

@Suite struct WorkoutFormatTests {
    @Test func clocks() {
        #expect(Format.clock(seconds: 3070) == "51:10")
        #expect(Format.clock(seconds: 3930) == "1:05:30")
    }

    @Test func pacesFollowTheSport() {
        let running = Format.pace(metresPerSecond: 1000.0 / 300, sport: .running)
        #expect(running == (Format.usesMiles ? "8:03 /mi" : "5:00 /km"))
        #expect(Format.pace(metresPerSecond: 1, sport: .swimming) == "1:40 /100 m")
        #expect(!Format.pace(metresPerSecond: 7.5, sport: .cycling).isEmpty)
        #expect(!Format.distance(metres: 10_000).isEmpty)
        #expect(!Format.elevation(metres: 640).isEmpty)
        #expect(!Format.hours(seconds: 9000).isEmpty)
    }

    @Test(
        arguments: [
            (0.5, "No benefit"), (1.5, "Minor benefit"), (2.5, "Maintaining"), (3.5, "Improving"),
            (4.5, "Highly improving"), (5.0, "Overreaching"),
        ] as [(Double, String)])
    func trainingEffects(value: Double, words: String) {
        #expect(Format.trainingEffect(value) == String(localized: String.LocalizationValue(words)))
    }

    @Test func garminsLabelsInWords() {
        #expect(Format.benefit("LACTATE_THRESHOLD") == String(localized: "Threshold"))
        #expect(Format.benefit("UNKNOWN") == nil)
        for label in [
            "RECOVERY", "AEROBIC_BASE", "TEMPO", "VO2MAX", "ANAEROBIC_CAPACITY", "SPRINT",
        ] {
            #expect(Format.benefit(label) != nil)
        }
        #expect(Format.trainingMessage("IMPROVING_VO2_MAX_15") == "Improving VO2 max")
        #expect(Format.trainingMessage("MAINTAINING_AEROBIC_BASE_1") == "Maintaining aerobic base")
        #expect(Format.trainingMessage("_1") == nil)
        #expect(Format.trainingMessage(nil) == nil)
    }
}
