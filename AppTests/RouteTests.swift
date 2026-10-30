import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A loop of `count` points around `center`, `radius` metres out, run `clockwise` or not.
nonisolated private func loop(
    center: GeoPoint, radius: Double, count: Int = 100, clockwise: Bool = false
) -> [GeoPoint] {
    (0...count).map { index in
        let angle = Double(index) / Double(count) * 2 * .pi * (clockwise ? -1 : 1)
        return GeoPoint(
            latitude: center.latitude + radius * sin(angle) / 111_320,
            longitude: center.longitude + radius * cos(angle)
                / (111_320 * cos(center.latitude * .pi / 180)))
    }
}

/// A workout of `sport` from `start` to `end` over `metres`.
nonisolated private func workout(
    _ id: Int, start: GeoPoint?, end: GeoPoint?, metres: Double, sport: String = "running"
) -> Workout? {
    Workout(
        SummarizedActivity(
            activityId: id,
            startTimeLocal: (try? GarminTime(hour: 7)).map {
                LocalDateTime(date: GarminDate.day("2026-10-20"), time: $0)
            },
            activityType: ActivityType(typeKey: sport), distance: metres, duration: 1800,
            startLatitude: start?.latitude, startLongitude: start?.longitude,
            endLatitude: end?.latitude, endLongitude: end?.longitude))
}

@Suite struct RouteMatcherTests {
    private let home = GeoPoint(latitude: 47.3605, longitude: 8.548)

    @Test func distancesOnTheEarth() {
        let north = GeoPoint(latitude: 48.3605, longitude: 8.548)
        #expect(abs(home.distance(to: north) - 111_195) < 10)
        #expect(home.distance(to: home) == 0)
        #expect(abs(home.distance(to: north) - north.distance(to: home)) < 1e-6)
    }

    @Test func resamplingKeepsTheEndsAndEvensTheSteps() throws {
        let route = [home, GeoPoint(latitude: 47.3705, longitude: 8.548)]
        let resampled = RouteMatcher.resample(route, count: 11)
        #expect(resampled.count == 11)
        #expect(try #require(resampled.first).distance(to: home) < 0.01)
        #expect(try #require(resampled.last).distance(to: route[1]) < 0.01)
        let steps = zip(resampled, resampled.dropFirst()).map { $0.distance(to: $1) }
        #expect(steps.allSatisfy { abs($0 - steps[0]) < 0.5 })
        #expect(RouteMatcher.resample([home]).count == 1)
        #expect(RouteMatcher.resample([home, home], count: 5) == [home])
    }

    @Test func theSameRouteInEitherDirection() {
        let route = loop(center: home, radius: 500)
        #expect(RouteMatcher.separation(route, route) < 1)
        let reversed = loop(center: home, radius: 500, clockwise: true)
        #expect(RouteMatcher.isSameRoute(route, reversed))
        // Sampled more sparsely, it is still the same route.
        #expect(RouteMatcher.isSameRoute(route, loop(center: home, radius: 500, count: 20)))
    }

    @Test func differentRoutesAreTold() {
        let route = loop(center: home, radius: 500)
        let bigger = loop(center: home, radius: 900)
        let elsewhere = loop(
            center: GeoPoint(latitude: 47.38, longitude: 8.548), radius: 500)
        #expect(!RouteMatcher.isSameRoute(route, bigger))
        #expect(!RouteMatcher.isSameRoute(route, elsewhere))
        #expect(RouteMatcher.separation(route, []) == .infinity)
    }

    @Test func candidatesShareSportEndsAndDistance() throws {
        let away = GeoPoint(latitude: 47.37, longitude: 8.548)
        let near = GeoPoint(latitude: 47.3606, longitude: 8.548)
        let run = try #require(workout(1, start: home, end: home, metres: 10_000))
        let pool = [
            run,
            try #require(workout(2, start: near, end: home, metres: 10_400)),
            try #require(workout(3, start: home, end: home, metres: 10_050)),
            try #require(workout(4, start: home, end: home, metres: 12_000)),
            try #require(workout(5, start: home, end: home, metres: 10_000, sport: "road_biking")),
            try #require(workout(6, start: away, end: home, metres: 10_000)),
            try #require(workout(7, start: nil, end: nil, metres: 10_000)),
        ]
        #expect(RouteMatcher.candidates(for: run, in: pool).map(\.id) == [3, 2])
        let unplaced = try #require(workout(8, start: nil, end: nil, metres: 10_000))
        #expect(RouteMatcher.candidates(for: unplaced, in: pool).isEmpty)
        #expect(
            try #require(
                workout(9, start: GeoPoint(latitude: 0, longitude: 0), end: home, metres: 1)
            )
            .startPoint == nil)
    }

    @Test func theDemoLoopEndsWhereItStarts() {
        let lap = SampleLoop.lap(for: 9100, about: 3000)
        #expect(abs(lap - 9100.0 / 3) < 1e-9)
        #expect(SampleLoop.point(at: 0, lap: lap) == SampleLoop.start)
        #expect(SampleLoop.point(at: 3 * lap, lap: lap).distance(to: SampleLoop.start) < 0.01)
        #expect(SampleLoop.point(at: lap / 2, lap: lap).distance(to: SampleLoop.start) > 500)
    }
}

@Suite struct CalendarMonthTests {
    private var mondayFirst: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = .gmt
        return calendar
    }

    @Test func monthArithmetic() {
        #expect(CalendarMonth.first(of: .day("2026-10-29")) == .day("2026-10-01"))
        #expect(CalendarMonth.adding(months: 1, to: .day("2026-12-01")) == .day("2027-01-01"))
        #expect(CalendarMonth.adding(months: -1, to: .day("2026-01-01")) == .day("2025-12-01"))
        #expect(CalendarMonth.adding(months: -13, to: .day("2026-10-01")) == .day("2025-09-01"))
        #expect(CalendarMonth.days(of: .day("2028-02-01")).count == 29)
        #expect(CalendarMonth.days(of: .day("2026-02-01")).count == 28)
        #expect(CalendarMonth.days(of: .day("2026-10-01")).last == .day("2026-10-31"))
    }

    @Test func weeksStartOnTheChosenDay() {
        // 1 October 2026 is a Thursday.
        #expect(CalendarMonth.leadingBlanks(of: .day("2026-10-01"), calendar: mondayFirst) == 3)
        var sundayFirst = mondayFirst
        sundayFirst.firstWeekday = 1
        #expect(CalendarMonth.leadingBlanks(of: .day("2026-10-01"), calendar: sundayFirst) == 4)
        let symbols = CalendarMonth.weekdaySymbols(calendar: mondayFirst)
        #expect(symbols.count == 7)
        #expect(symbols.first == mondayFirst.veryShortStandaloneWeekdaySymbols[1])
        #expect(symbols.last == mondayFirst.veryShortStandaloneWeekdaySymbols[0])
    }
}

/// Counts the months fetched.
private actor Fetches {
    var months: [String] = []

    func record(_ first: GarminDate) {
        months.append("\(first)")
    }
}

@Suite struct ActivityArchiveTests {
    private let end = GarminDate.day("2026-10-29")

    @Test func monthsComeFromTheLoadedDataOrAreFetchedOnce() async throws {
        let fetches = Fetches()
        let model = TrainingModel(
            today: { end }, fetch: { end, _ in .sample(endingOn: end) },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) },
            fetchActivities: { first, _ in
                await fetches.record(first)
                return []
            })
        #expect(model.workouts(inMonthStarting: .day("2026-10-01")) == nil)
        await model.load()
        let october = try #require(model.workouts(inMonthStarting: .day("2026-10-01")))
        #expect(!october.isEmpty)
        #expect(october.allSatisfy { $0.date.month == 10 && $0.date.year == 2026 })
        #expect(model.workouts(inMonthStarting: .day("2025-10-01")) == nil)
        await model.loadMonth(startingOn: .day("2025-10-01"))
        await model.loadMonth(startingOn: .day("2025-10-01"))
        await model.loadMonth(startingOn: .day("2026-10-01"))
        #expect(model.workouts(inMonthStarting: .day("2025-10-01"))?.isEmpty == true)
        #expect(await fetches.months == ["2025-10-01"])
    }

    @Test func aFailedMonthCanBeRetried() async {
        let model = TrainingModel(
            today: { end }, fetch: { end, _ in .sample(endingOn: end) },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) },
            fetchActivities: { _, _ in throw Problem.offline })
        await model.loadMonth(startingOn: .day("2025-10-01"))
        #expect(model.archiveProblems[.day("2025-10-01")] == .offline)
    }

    @Test func theHistoryKeepsTheWarmUpActivities() {
        let data = TrainingData.sample(endingOn: end)
        #expect(data.history.count > data.workouts.count)
        #expect(Set(data.workouts.map(\.id)).isSubset(of: Set(data.history.map(\.id))))
    }

    @Test func theDemoFindsRunsOnTheSameRoute() async throws {
        let model = TrainingModel(client: try client(DemoTransport()))
        await model.load()
        guard case .loaded(let data) = model.phase else {
            Issue.record("no data")
            return
        }
        let runs = data.workouts.filter { $0.sport == .running }
        let run = try #require(
            runs.first { run in !RouteMatcher.candidates(for: run, in: data.history).isEmpty })
        await model.findSimilarRoutes(to: run)
        guard case .found(let matches) = model.similar[run.id] else {
            Issue.record("no search result")
            return
        }
        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { $0.sport == .running && $0.id != run.id })
        let strength = try #require(data.workouts.first { $0.sport == .strength })
        await model.findSimilarRoutes(to: strength)
        #expect(model.similar[strength.id] == .found([]))
    }
}
