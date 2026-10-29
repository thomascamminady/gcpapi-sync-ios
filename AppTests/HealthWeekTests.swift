import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

@Suite struct HealthWeekTests {
    private let monday = GarminDate.day("2026-10-19")

    @Test func assembleMapsGarminsModels() {
        let tuesday = monday.adding(days: 1)
        let week = HealthWeekLoader.assemble(
            dates: [monday, tuesday],
            summaries: [
                UserDailySummaryV2(
                    calendarDate: monday,
                    movement: MovementV2(steps: MovementValueV2(goal: 8000, value: 9123)),
                    calories: CaloriesV2(burnedActive: 512),
                    heartRate: HeartRateV2(restingValue: 47),
                    intensityMinutes: IntensityMinutesV2(moderate: 20, vigorous: 15),
                    stress: StressV2(avgLevel: 31),
                    bodyBattery: BodyBatteryV2(minValue: 15, maxValue: 92)),
                UserDailySummaryV2(calendarDate: tuesday, stress: StressV2(avgLevel: -2)),
            ],
            sleep: [
                DailySleep(
                    calendarDate: monday, sleepTimeSeconds: 27_000, deepSleepSeconds: 5400,
                    lightSleepSeconds: 14_400, remSleepSeconds: 7200, awakeSleepSeconds: 600,
                    sleepScores: SleepScores(overall: SleepScoreItem(value: 84))),
                DailySleep(calendarDate: tuesday, sleepTimeSeconds: 0),
            ],
            hrv: [HrvSummary(calendarDate: monday, lastNightAvg: 61, status: "BALANCED")]
        )

        let first = week.days[0]
        #expect(first.steps == 9123)
        #expect(first.stepGoal == 8000)
        #expect(first.restingHeartRate == 47)
        #expect(first.stress == 31)
        #expect(first.bodyBatteryLow == 15)
        #expect(first.bodyBatteryHigh == 92)
        #expect(first.activeCalories == 512)
        #expect(first.intensityMinutes == 50)
        #expect(first.hrv == 61)
        #expect(first.hrvStatus == "BALANCED")
        #expect(
            first.sleep
                == SleepNight(
                    total: 27_000, deep: 5400, light: 14_400, rem: 7200, awake: 600, score: 84))
        let second = week.days[1]
        #expect(second.stress == nil, "negative stress means not enough data")
        #expect(second.sleep == nil, "a night without sleep time is no night")
        #expect(second.intensityMinutes == nil)
        #expect(second.hrv == nil)
    }

    @Test func daysWithoutDataStayEmpty() {
        let week = HealthWeekLoader.assemble(dates: [monday], summaries: [], sleep: [], hrv: [])
        #expect(week.days == [DayHealth(date: monday)])
        #expect(week.average(\.steps) == nil)
        #expect(week.latest(\.hrv) == nil)
        #expect(week.total(\.intensityMinutes) == 0)
        #expect(week.averageSleep == nil)
    }

    @Test func aggregates() {
        var days = (0..<3).map { DayHealth(date: monday.adding(days: $0)) }
        days[0].steps = 1000
        days[2].steps = 2001
        days[0].hrv = 50
        days[1].hrv = 60
        days[0].intensityMinutes = 30
        days[2].intensityMinutes = 45
        days[0].sleep = SleepNight(
            total: 3600, deep: 600, light: 1800, rem: 900, awake: 300, score: 70)
        days[1].sleep = SleepNight(
            total: 7200, deep: 1200, light: 3600, rem: 1800, awake: 600, score: nil)
        let week = HealthWeek(days: days)
        #expect(week.average(\.steps) == 1501)
        #expect(week.latest(\.hrv) == 60)
        #expect(week.total(\.intensityMinutes) == 75)
        #expect(
            week.averageSleep
                == SleepNight(total: 5400, deep: 900, light: 2700, rem: 1350, awake: 450, score: 70)
        )
    }

    @Test func loadsAWeekThroughGarminsJSON() async throws {
        // The demo answers in Garmin's own format, so this runs the full decoding path.
        let end = GarminDate.day("2026-10-28")
        let week = try await HealthWeekLoader.load(from: try client(DemoTransport()), endingOn: end)
        #expect(week == HealthWeek.sample(endingOn: end))
        #expect(week.days.count == 7)
        #expect(week.days.first?.date == .day("2026-10-22"))
    }

    @Test func loadAsksForTheWeekOnce() async throws {
        let transport = StubTransport { request in
            switch request.path {
            case tokenPath: (200, "token")
            case "/usersummary-service/v2/dailysummaries": (200, #"{"data": []}"#)
            case "/sleep-service/sleep/dailySleepSummariesByDate": (200, "[]")
            default: (200, #"{"hrvSummaries": []}"#)
            }
        }
        let week = try await HealthWeekLoader.load(
            from: try client(transport), endingOn: .day("2026-10-28"))
        #expect(week.days.count == 7)
        let paths = await transport.requests.map(\.path).filter { $0 != tokenPath }.sorted()
        #expect(
            paths == [
                "/hrv-service/hrv/daily/2026-10-22/2026-10-28",
                "/sleep-service/sleep/dailySleepSummariesByDate",
                "/usersummary-service/v2/dailysummaries",
            ])
    }
}
