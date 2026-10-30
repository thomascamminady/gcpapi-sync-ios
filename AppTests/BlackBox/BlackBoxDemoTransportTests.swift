import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// The demo's synthetic Garmin, through a real client.
@Suite struct BlackBoxDemoTransportTests {
    private let end = BlackBox.today
    private var start: GarminDate { end.adding(days: -6) }

    private func demo() throws -> GarminClient {
        try client(DemoTransport(), apiKey: "demo-key")
    }

    private func range(_ first: GarminDate, _ last: GarminDate) -> ActivityFilters {
        ActivityFilters(startDate: first, endDate: last)
    }

    /// Every date from `first` through `last`.
    private func dates(_ first: GarminDate, _ last: GarminDate) -> [GarminDate] {
        (0...first.days(to: last)).map { first.adding(days: $0) }
    }

    // MARK: - Endpoints

    @Test func theKeyExchangeWorks() async throws {
        let token = try await demo().getAccessToken(forceRefresh: true)
        #expect(!token.value.isEmpty)
        #expect(!token.expires(within: 60))
    }

    @Test func dailySummariesCoverEveryDay() async throws {
        let summaries = try await demo().getDailySummaries(start: start, end: end)
        #expect(Set(summaries.compactMap(\.calendarDate)) == Set(dates(start, end)))
    }

    @Test func sleepAndHRVAreWithinTheRange() async throws {
        let client = try demo()
        let sleep = try await client.getDailySleepSummaries(start: start, end: end)
        let hrv = try await client.getDailyHRVSummaries(start: start, end: end)
        #expect(!sleep.isEmpty)
        #expect(!hrv.isEmpty)
        let days = Set(dates(start, end))
        #expect(sleep.compactMap(\.calendarDate).allSatisfy(days.contains))
        #expect(hrv.compactMap(\.calendarDate).allSatisfy(days.contains))
    }

    @Test func longRangesAreAnsweredToo() async throws {
        let first = end.adding(days: -89)
        let summaries = try await demo().getDailySummaries(start: first, end: end)
        #expect(Set(summaries.compactMap(\.calendarDate)) == Set(dates(first, end)))
    }

    @Test func heartRateZonesHaveAMaximum() async throws {
        let zones = try await demo().getHeartRateZones()
        #expect(!zones.isEmpty)
        #expect(zones.contains { ($0.maxHeartRateUsed ?? 0) > 100 })
    }

    // MARK: - Activities

    @Test func activitiesAreWithinTheSearchedDays() async throws {
        let first = end.adding(days: -27)
        let activities = try await demo().searchActivities(
            start: 0, limit: 200, filters: range(first, end))
        #expect(!activities.isEmpty)
        for activity in activities {
            let day = try #require(activity.startTimeLocal?.date)
            #expect(day >= first && day <= end, "\(day)")
        }
        #expect(Set(activities.map(\.activityId)).count == activities.count)
    }

    @Test func activitiesAreTheDemosActivities() async throws {
        let first = end.adding(days: -13)
        let activities = try await demo().searchActivities(
            start: 0, limit: 200, filters: range(first, end))
        let expected = dates(first, end).flatMap(SummarizedActivity.sampleActivities(on:))
        #expect(Set(activities.map(\.activityId)) == Set(expected.map(\.activityId)))
        for activity in activities {
            #expect(
                SummarizedActivity.sample(id: activity.activityId)?.activityId
                    == activity.activityId)
        }
    }

    @Test(arguments: [1, 3, 5, 7, 20])
    func pagesJoinUpToTheWholeSearch(pageSize: Int) async throws {
        let client = try demo()
        let filters = range(end.adding(days: -59), end)
        let whole = try await client.searchActivities(start: 0, limit: 500, filters: filters)
        #expect(whole.count > pageSize)
        var paged: [Int] = []
        var offset = 0
        while true {
            let page = try await client.searchActivities(
                start: offset, limit: pageSize, filters: filters)
            #expect(page.count <= pageSize)
            paged += page.map(\.activityId)
            offset += page.count
            if page.count < pageSize { break }
        }
        #expect(paged == whole.map(\.activityId))
    }

    @Test func aSearchPastTheEndIsEmpty() async throws {
        let client = try demo()
        let filters = range(end.adding(days: -6), end)
        let whole = try await client.searchActivities(start: 0, limit: 100, filters: filters)
        let beyond = try await client.searchActivities(
            start: whole.count, limit: 10, filters: filters)
        #expect(beyond.isEmpty)
        let limited = try await client.searchActivities(start: 0, limit: 1, filters: filters)
        #expect(limited.map(\.activityId) == whole.prefix(1).map(\.activityId))
    }

    @Test func iteratingPagesFindsEveryActivity() async throws {
        let client = try demo()
        let filters = range(end.adding(days: -20), end)
        let whole = try await client.searchActivities(start: 0, limit: 500, filters: filters)
        var iterated: [Int] = []
        for try await activity in try client.iterActivities(pageSize: 4, filters: filters) {
            iterated.append(activity.activityId)
        }
        #expect(iterated == whole.map(\.activityId))
    }

    // MARK: - Downloads

    @Test func activityDownloadsAreZips() async throws {
        let client = try demo()
        let activities = try await client.searchActivities(
            start: 0, limit: 3, filters: range(end.adding(days: -13), end))
        let activity = try #require(activities.first)
        let zip = try await client.downloadActivityZip(activity.activityId)
        #expect(zip.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
    }

    @Test func downloadedRecordingsAreFIT() async throws {
        let client = try demo()
        let activities = try await client.searchActivities(
            start: 0, limit: 20, filters: range(end.adding(days: -13), end))
        #expect(!activities.isEmpty)
        for activity in activities.prefix(5) {
            let file = try await client.downloadActivity(activity.activityId)
            #expect(file.activityID == activity.activityId)
            #expect(file.fileExtension == "fit")
            let fit = try FITActivity(decoding: file.content)
            #expect(!fit.records.isEmpty || !fit.sets.isEmpty, "\(activity.activityId)")
        }
    }

    // MARK: - Everything else

    @Test(arguments: [
        "/no-such-service/anything", "/", "/usersummary-service/unknown",
        "/activitylist-service/activities/search/activities/extra",
    ])
    func unknownPathsAreNotFound(path: String) async throws {
        let client = try demo()
        await #expect(throws: NotFoundError.self) { _ = try await client.getJSON(path) }
    }

    @Test func unknownPathsAnswer404Directly() throws {
        let url = try #require(URL(string: "https://personal.connectapi.garmin.com/nope"))
        let request = HTTPRequest(method: "GET", url: url, headers: [:])
        let response = try DemoTransport().send(request)
        #expect(response.statusCode == 404)
        #expect(response.request.url == url)
    }

    @Test func theDashboardLoadsFromTheDemo() async throws {
        let history = try await HealthLoader.load(from: demo(), endingOn: end, days: 7)
        #expect(history.days.map(\.date) == dates(start, end))
        for metric in Metric.allCases {
            #expect(history.days.contains { metric.hasValue($0) }, "\(metric)")
        }
    }

    @Test func trainingLoadsFromTheDemo() async throws {
        let data = try await TrainingLoader.load(from: demo(), endingOn: end)
        #expect(!data.workouts.isEmpty)
        #expect(!data.weeks.isEmpty)
        #expect(data.heartRateZones(for: .running) != nil)
        // Newest first, whatever order the demo answers in.
        let dates = data.workouts.map(\.date)
        #expect(dates == dates.sorted(by: >))
        #expect(data.weeks.map(\.start) == data.weeks.map(\.start).sorted())
    }
}

/// Query parameters by name.
@Suite struct BlackBoxHTTPQueryTests {
    private func request(_ text: String) throws -> HTTPRequest {
        HTTPRequest(method: "GET", url: try #require(URL(string: text)), headers: [:])
    }

    @Test func parametersByName() throws {
        let query = try request("https://example.com/path?start=0&limit=20&q=x").query
        #expect(query == ["start": "0", "limit": "20", "q": "x"])
    }

    @Test func theLastValueWins() throws {
        #expect(try request("https://example.com/p?a=1&b=2&a=3").query == ["a": "3", "b": "2"])
    }

    @Test func noQueryIsEmpty() throws {
        #expect(try request("https://example.com/path").query.isEmpty)
        #expect(try request("https://example.com/path?").query.isEmpty)
    }

    @Test func valuesAreDecoded() throws {
        let query = try request("https://example.com/p?name=a%20b&date=2026-10-30&e=").query
        #expect(query["name"] == "a b")
        #expect(query["date"] == "2026-10-30")
        #expect(query["e"]?.isEmpty == true)
    }

    @Test func theClientsQueryIsReadBack() async throws {
        let transport = garmin()
        let api = try client(transport, apiKey: "good-key")
        _ = try? await api.searchActivities(start: 5, limit: 7)
        let search = await transport.requests.last
        #expect(search?.query["start"] == "5")
        #expect(search?.query["limit"] == "7")
    }
}
