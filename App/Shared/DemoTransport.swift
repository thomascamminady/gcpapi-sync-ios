import Foundation
import GCPAPISync

/// Answers the requests the dashboard makes with synthetic data in Garmin's own JSON
/// format, so the app can be explored (and reviewed) without a Garmin account.
nonisolated struct DemoTransport: HTTPTransport {
    func send(_ request: HTTPRequest) throws -> HTTPResponse {
        let path = request.path
        let body: Data
        if path.hasSuffix("/personal-api-key/token") {
            body = Data("demo-access-token".utf8)
        } else if path == "/usersummary-service/v2/dailysummaries" {
            body = try JSONEncoder().encode(
                UserDailySummaryV2List(data: days(request.query).map(Self.summary)))
        } else if path == "/sleep-service/sleep/dailySleepSummariesByDate" {
            body = try JSONEncoder().encode(days(request.query).map(Self.sleep))
        } else if path.hasPrefix("/hrv-service/hrv/daily/") {
            let parts = path.split(separator: "/").suffix(2).map(String.init)
            body = try JSONEncoder().encode(
                HrvDailySummary(hrvSummaries: days(from: parts.first, to: parts.last).map(Self.hrv))
            )
        } else if path == "/biometric-service/heartRateZones/v2" {
            body = try JSONEncoder().encode([HeartRateZones.sample])
        } else if path == "/activitylist-service/activities/search/activities" {
            body = try JSONEncoder().encode(runs(request.query))
        } else {
            return HTTPResponse(statusCode: 404, body: Data(), request: request)
        }
        return HTTPResponse(
            statusCode: 200, body: body, request: request,
            headers: ["Content-Type": "application/json"])
    }

    private func days(_ query: [String: String]) -> [DayHealth] {
        days(from: query["startDate"], to: query["endDate"])
    }

    private func days(from start: String?, to end: String?) -> [DayHealth] {
        dates(from: start, to: end).map(DayHealth.sample)
    }

    private func dates(from start: String?, to end: String?) -> [GarminDate] {
        guard let first = try? GarminDate(start ?? ""), let last = try? GarminDate(end ?? "") else {
            return []
        }
        return (0...max(0, first.days(to: last))).map { first.adding(days: $0) }
    }

    /// The page of runs `query` asks for, oldest first.
    private func runs(_ query: [String: String]) -> [SummarizedActivity] {
        let runs = dates(from: query["startDate"], to: query["endDate"])
            .compactMap(SummarizedActivity.sampleRun)
        let start = min(Int(query["start"] ?? "") ?? 0, runs.count)
        let limit = Int(query["limit"] ?? "") ?? runs.count
        return Array(runs[start...].prefix(limit))
    }

    private static func summary(_ day: DayHealth) -> UserDailySummaryV2 {
        UserDailySummaryV2(
            calendarDate: day.date,
            movement: MovementV2(steps: MovementValueV2(goal: day.stepGoal, value: day.steps)),
            calories: CaloriesV2(burnedActive: day.activeCalories),
            heartRate: HeartRateV2(restingValue: day.restingHeartRate),
            intensityMinutes: IntensityMinutesV2(
                goal: 150, moderate: day.intensityMinutes, vigorous: 0),
            stress: StressV2(avgLevel: day.stress),
            bodyBattery: BodyBatteryV2(minValue: day.bodyBatteryLow, maxValue: day.bodyBatteryHigh)
        )
    }

    private static func sleep(_ day: DayHealth) -> DailySleep {
        DailySleep(
            calendarDate: day.date,
            sleepTimeSeconds: day.sleep?.total,
            deepSleepSeconds: day.sleep?.deep,
            lightSleepSeconds: day.sleep?.light,
            remSleepSeconds: day.sleep?.rem,
            awakeSleepSeconds: day.sleep?.awake,
            sleepScores: SleepScores(overall: SleepScoreItem(value: day.sleep?.score))
        )
    }

    private static func hrv(_ day: DayHealth) -> HrvSummary {
        HrvSummary(calendarDate: day.date, lastNightAvg: day.hrv, status: day.hrvStatus)
    }
}

extension HTTPRequest {
    /// The query parameters by name (the last value wins).
    nonisolated var query: [String: String] {
        Dictionary(queryItems.map { ($0.name, $0.value) }) { _, last in last }
    }
}
