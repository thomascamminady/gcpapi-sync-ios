import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// SplitMix64: a tiny deterministic generator, so that randomized inputs repeat exactly.
nonisolated struct BlackBoxRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A uniform value in `range`.
    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / 9_007_199_254_740_992
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    /// A uniform integer in `range`.
    mutating func integer(_ range: ClosedRange<Int>) -> Int {
        Int.random(in: range, using: &self)
    }
}

/// Builders and checks shared by the black-box suites.
nonisolated enum AnalyticsBlackBox {
    /// A Friday.
    static let reference = GarminDate.day("2026-10-30")

    /// Whether two values agree to a relative (or, near zero, absolute) tolerance.
    static func isClose(_ lhs: Double, _ rhs: Double, tolerance: Double = 1e-9) -> Bool {
        abs(lhs - rhs) <= tolerance * max(1, abs(lhs), abs(rhs))
    }

    /// `count` consecutive dates starting at `first`.
    static func dates(from first: GarminDate, count: Int) -> [GarminDate] {
        (0..<max(0, count)).map { first.adding(days: $0) }
    }

    /// A calendar with the given first weekday (1 is Sunday) in `zone`.
    static func calendar(
        firstWeekday: Int, zone: String = "UTC", identifier: Calendar.Identifier = .gregorian
    ) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.firstWeekday = firstWeekday
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }

    /// The weekday (1 is Sunday) of `date`, computed independently of any calendar setting.
    static func weekday(of date: GarminDate) -> Int {
        // 2026-10-25 is a Sunday.
        let offset = GarminDate.day("2026-10-25").days(to: date)
        return ((offset % 7) + 7) % 7 + 1
    }

    /// A Garmin activity starting at `hour` o'clock (UTC and local alike) on `date`.
    static func activity(
        id: Int, on date: GarminDate, hour: Int = 7, typeKey: String? = "running",
        duration: Double? = 3600, distance: Double? = 10_000, load: Double? = 100,
        speed: Double? = nil, gradeAdjusted: Double? = nil, heartRate: Double? = nil,
        maxHeartRate: Double? = nil, name: String? = nil
    ) -> SummarizedActivity {
        let local = (try? GarminTime(hour: hour)).map { LocalDateTime(date: date, time: $0) }
        return SummarizedActivity(
            activityId: id,
            activityName: name ?? "Activity \(id)",
            startTimeLocal: local,
            startTimeGMT: local?.date(in: .gmt),
            activityType: typeKey.map { ActivityType(typeKey: $0) },
            distance: distance,
            duration: duration,
            averageSpeed: speed,
            averageHR: heartRate,
            maxHR: maxHeartRate,
            activityTrainingLoad: load,
            avgGradeAdjustedSpeed: gradeAdjusted
        )
    }

    /// The workout of a plain activity on `date` with `load`.
    static func workout(
        id: Int, on date: GarminDate, load: Double?, typeKey: String = "running",
        duration: Double = 3600
    ) throws -> Workout {
        let activity = activity(
            id: id, on: date, typeKey: typeKey, duration: duration, load: load)
        return try #require(Workout(activity))
    }

    /// One workout per entry of `loads`, on consecutive days from `first`; zero loads are
    /// left out, as rest days.
    static func workouts(_ loads: [Double], from first: GarminDate) throws -> [Workout] {
        var result: [Workout] = []
        for (offset, load) in loads.enumerated() where load > 0 {
            result.append(try workout(id: offset + 1, on: first.adding(days: offset), load: load))
        }
        return result
    }

    /// Heart rate zones for `sport` with floors `floors` and a maximum.
    static func zones(
        _ sport: String?, floors: [Int?] = [100, 120, 140, 160, 175], maximum: Int? = 190
    ) -> HeartRateZones {
        func floor(_ index: Int) -> Int? {
            index < floors.count ? floors[index] : nil
        }
        return HeartRateZones(
            zone1Floor: floor(0), zone2Floor: floor(1), zone3Floor: floor(2),
            zone4Floor: floor(3), zone5Floor: floor(4), maxHeartRateUsed: maximum, sport: sport
        )
    }

    /// A night of `hours` hours with a score.
    static func night(hours: Double, score: Int?) -> SleepNight {
        let total = Int(hours * 3600)
        return SleepNight(
            total: total, deep: total / 5, light: total / 2, rem: total / 5, awake: 600,
            score: score)
    }

    /// The query of `request` as a dictionary (the last value of a repeated name wins).
    static func query(_ request: HTTPRequest) -> [String: String] {
        var result: [String: String] = [:]
        for item in request.queryItems {
            result[item.name] = item.value
        }
        return result
    }

    /// Whether `request` is an activity search.
    static func isSearch(_ request: HTTPRequest) -> Bool {
        request.path.hasSuffix("/activities/search/activities")
    }

    /// The JSON of an activity on `date`, as the activity search returns it.
    static func activityJSON(id: Int, on date: GarminDate, load: Double = 50) -> String {
        """
        {"activityId":\(id),"activityName":"Run \(id)",\
        "startTimeLocal":"\(date)T07:00:00","startTimeGMT":"\(date)T06:00:00",\
        "activityType":{"typeKey":"running"},"duration":1800,"distance":5000,\
        "activityTrainingLoad":\(load)}
        """
    }

    /// A client of `transport` that never retries.
    static func client(of transport: any HTTPTransport) throws -> GarminClient {
        try GarminClient(
            apiKey: "black-box-key", retry: RetryConfig(maxRetries: 0), transport: transport)
    }
}

/// Answers a test's requests: the token exchange, and activity searches from `activities`,
/// paged as Garmin pages them.
nonisolated struct BlackBoxSearchResponder: Sendable {
    /// The ids of the activities on a day.
    let activities: @Sendable (GarminDate) -> [Int]
    /// The heart rate zones endpoint's answer.
    var zones = "[]"
    /// A day whose window fails with HTTP 400.
    var failing: GarminDate?

    func respond(_ request: HTTPRequest) -> (status: Int, body: String) {
        if request.path.contains("personalapitoken") {
            return (200, "black-box-token")
        }
        if request.path.contains("heartRateZones") {
            return (200, zones)
        }
        guard AnalyticsBlackBox.isSearch(request) else {
            return (200, "[]")
        }
        let query = AnalyticsBlackBox.query(request)
        guard let first = query["startDate"].flatMap({ try? GarminDate($0) }),
            let last = query["endDate"].flatMap({ try? GarminDate($0) })
        else {
            return (400, "{\"message\":\"missing dates\"}")
        }
        if let failing, first <= failing, failing <= last {
            return (400, "{\"message\":\"black-box failure\"}")
        }
        let start = query["start"].flatMap { Int($0) } ?? 0
        let limit = query["limit"].flatMap { Int($0) } ?? 20
        var entries: [String] = []
        var date = last
        while date >= first {
            for id in activities(date) {
                entries.append(AnalyticsBlackBox.activityJSON(id: id, on: date))
            }
            date = date.adding(days: -1)
        }
        let page = entries.dropFirst(start).prefix(limit)
        return (200, "[" + page.joined(separator: ",") + "]")
    }
}

/// Counts how many activity searches are in flight at once.
actor BlackBoxFlightGauge {
    private(set) var inFlight = 0
    private(set) var maximum = 0
    private(set) var searches = 0

    func begin() {
        inFlight += 1
        searches += 1
        maximum = max(maximum, inFlight)
    }

    func end() {
        inFlight -= 1
    }
}

/// A transport whose activity searches take a while, to observe concurrency.
nonisolated struct BlackBoxSlowTransport: HTTPTransport {
    let gauge: BlackBoxFlightGauge
    let responder: BlackBoxSearchResponder

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if AnalyticsBlackBox.isSearch(request) {
            await gauge.begin()
            try await Task.sleep(for: .milliseconds(40))
            await gauge.end()
        }
        let (status, body) = responder.respond(request)
        return HTTPResponse(statusCode: status, body: Data(body.utf8), request: request)
    }
}

/// Records calls to an injected fetch and answers them from a script.
actor BlackBoxScript<Value: Sendable> {
    /// What a call does.
    enum Step: Sendable {
        case value(Value)
        case failure(any Error & Sendable)
        case cancellation
    }

    private var steps: [Step]
    private let fallback: Step
    private(set) var calls: [String] = []

    init(_ steps: [Step], otherwise fallback: Step) {
        self.steps = steps
        self.fallback = fallback
    }

    /// The call count.
    var count: Int { calls.count }

    /// Record a call described by `label` and play the next step.
    func play(_ label: String) throws -> Value {
        calls.append(label)
        let step = steps.isEmpty ? fallback : steps.removeFirst()
        switch step {
        case .value(let value):
            return value
        case .failure(let error):
            throw error
        case .cancellation:
            throw CancellationError()
        }
    }
}

/// An error the injected closures throw.
nonisolated struct BlackBoxError: Error, Equatable {
    let code: Int
}

/// A clock the models read, which tests move forward.
final class BlackBoxClock {
    var now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_793_340_000)) {
        self.now = now
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}
