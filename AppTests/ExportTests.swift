import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// A directory of its own, deleted when the test is done.
private final class ExportDirectory {
    let url = URL.temporaryDirectory.appending(path: "export-tests-\(UUID().uuidString)")

    init() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite struct ExporterTests {
    private let end = GarminDate.day("2026-10-29")

    private var workouts: [Workout] {
        TrainingData.sample(endingOn: end).workouts
    }

    @Test func csvFieldsAreQuotedWhenNeeded() {
        #expect(Exporter.escape("plain") == "plain")
        #expect(Exporter.escape("a,b") == "\"a,b\"")
        #expect(Exporter.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(Exporter.escape("two\nlines") == "\"two\nlines\"")
    }

    @Test func csvRoundTrips() {
        let rows = [["1", "Run, easy", "say \"hi\""], ["2", "two\nlines", ""]]
        let text = Exporter.csv(header: ["id", "name", "note"], rows: rows)
        #expect(Exporter.parse(text) == [["id", "name", "note"]] + rows)
        #expect(Exporter.parse("a,b\r\nc,d\r\n") == [["a", "b"], ["c", "d"]])
        #expect(Exporter.parse("").isEmpty)
    }

    @Test func dailyAndActivityTables() {
        let days = HealthHistory.sample(endingOn: end).days
        let daily = Exporter.parse(Exporter.dailyCSV(days.reversed()))
        #expect(daily.first == Exporter.dailyHeader)
        #expect(daily.count == days.count + 1)
        #expect(daily.dropFirst().allSatisfy { $0.count == Exporter.dailyHeader.count })
        #expect(daily[1][0] == "\(days[0].date)")
        let activities = Exporter.parse(Exporter.activitiesCSV(workouts))
        #expect(activities.count == workouts.count + 1)
        #expect(activities.dropFirst().allSatisfy { $0.count == Exporter.activityHeader.count })
        // Numbers use a dot, whatever the region.
        #expect(Exporter.number(1234.5) == "1234.5")
        #expect(Exporter.number(3) == "3")
        #expect(!Exporter.dailyCSV(days).contains("1.234"))
    }

    @Test func mergingKeepsEarlierRows() {
        let header = ["key", "value"]
        let first = Exporter.merge(
            nil, header: header, rows: [["a", "1"], ["b", "2"]], newestFirst: false)
        let second = Exporter.merge(
            first, header: header, rows: [["b", "3"], ["c", "4"]], newestFirst: false)
        #expect(Exporter.parse(second) == [header, ["a", "1"], ["b", "3"], ["c", "4"]])
        let newest = Exporter.merge(second, header: header, rows: [], newestFirst: true)
        #expect(Exporter.parse(newest).dropFirst().map(\.first) == ["c", "b", "a"])
    }

    @Test func jsonHoldsEverything() throws {
        let days = HealthHistory.sample(endingOn: end).days
        let data = try Exporter.json(days: days, workouts: workouts)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["days"] as? [Any])?.count == days.count)
        #expect((object["activities"] as? [Any])?.count == workouts.count)
    }

    @Test func calendarFilesFollowTheStandard() throws {
        let text = Exporter.calendar(workouts, now: Date(timeIntervalSince1970: 1_800_000_000))
        let lines = text.components(separatedBy: "\r\n")
        #expect(lines.first == "BEGIN:VCALENDAR")
        #expect(lines.contains("END:VCALENDAR"))
        #expect(lines.filter { $0 == "BEGIN:VEVENT" }.count == workouts.count)
        #expect(lines.allSatisfy { $0.utf8.count <= 75 })
        let first = try #require(workouts.first)
        #expect(text.contains("UID:garmin-activity-\(first.id)@gcpapi-sync"))
        #expect(text.contains("DTSTAMP:20270115T080000Z"))
        // A comma in a summary is escaped.
        #expect(
            !text.components(separatedBy: "\r\n").contains {
                $0.hasPrefix("SUMMARY:") && $0.contains(",") && !$0.contains("\\,")
            })
    }

    @Test func gpxTracks() throws {
        let run = try #require(
            (0..<7).lazy.compactMap { SummarizedActivity.sampleRun(on: end.adding(days: -$0)) }
                .first)
        let recording = FITActivity.sample(of: run)
        let gpx = Exporter.gpx(recording, name: "Run <& friends>")
        #expect(gpx.hasPrefix("<?xml"))
        #expect(gpx.contains("<name>Run &lt;&amp; friends&gt;</name>"))
        #expect(gpx.components(separatedBy: "<trkpt").count - 1 == recording.records.count)
        #expect(gpx.contains("<ele>"))
    }

    @Test func calendarTexts() throws {
        let run = try #require(workouts.first { $0.distance != nil })
        #expect(CalendarText.title(of: run).hasPrefix(run.name + " · "))
        #expect(CalendarText.notes(of: run).contains(Format.clock(seconds: run.duration)))
        #expect(CalendarText.link(of: run).absoluteString.hasSuffix("/\(run.id)"))
        let strength = try #require(workouts.first { $0.distance == nil })
        #expect(
            CalendarText.title(of: strength).hasSuffix(Format.clock(seconds: strength.duration)))
    }
}

@Suite struct DataExportTests {
    private let end = GarminDate.day("2026-10-29")

    @Test func preparesTheChosenFiles() async throws {
        let scratch = ExportDirectory()
        let export = DataExport(
            directory: scratch.url,
            fetchHealth: { end, days in .sample(endingOn: end, days: days) },
            fetchActivities: { _, last in TrainingData.sample(endingOn: last).workouts })
        #expect(export.phase == .idle)
        await export.prepare(days: 30, contents: [.daily, .calendar, .json], today: end)
        guard case .ready(let files) = export.phase else {
            Issue.record("no files")
            return
        }
        #expect(files.map(\.pathExtension) == ["csv", "ics", "json"])
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        let daily = try String(contentsOf: files[0], encoding: .utf8)
        #expect(Exporter.parse(daily).count == 31)
        export.reset()
        #expect(export.phase == .idle)
    }

    @Test func aFailedExportSaysWhy() async {
        let export = DataExport(
            directory: ExportDirectory().url,
            fetchHealth: { _, _ in throw Problem.offline },
            fetchActivities: { _, _ in [] })
        await export.prepare(days: 7, contents: [.daily], today: end)
        #expect(export.phase == .failed(.offline))
    }

    @Test func foldersGrowIntoAHistory() throws {
        let scratch = ExportDirectory()
        let week = HealthHistory.sample(endingOn: end).days
        let earlier = HealthHistory.sample(endingOn: end.adding(days: -7)).days
        let workouts = TrainingData.sample(endingOn: end).workouts
        try FolderSync.write(days: earlier, workouts: Array(workouts.suffix(3)), to: scratch.url)
        try FolderSync.write(days: week, workouts: Array(workouts.prefix(3)), to: scratch.url)
        let daily = try String(
            contentsOf: scratch.url.appending(path: FolderSync.dailyFile), encoding: .utf8)
        #expect(Exporter.parse(daily).count == 15)
        let activities = try String(
            contentsOf: scratch.url.appending(path: FolderSync.activitiesFile), encoding: .utf8)
        #expect(Exporter.parse(activities).count == 7)
    }

    @Test func noFolderMeansNoExport() throws {
        let defaults = UserDefaults(suiteName: "export-tests-\(UUID().uuidString)") ?? .standard
        let folder = FolderSync(defaults: defaults)
        #expect(folder.folder == nil)
        try folder.export(days: HealthHistory.sample(endingOn: end).days, workouts: [])
        folder.forget()
    }
}

@Suite struct LicenseTests {
    @Test(arguments: LicensesView.components)
    func everyLicenseIsBundled(component: LicensesView.Component) {
        #expect(component.text.count > 500)
    }

    @Test func theApacheNoticeIsIncluded() throws {
        let log = try #require(LicensesView.components.first { $0.file == "swift-log" })
        #expect(log.text.contains("Apache License"))
        #expect(log.text.contains("NOTICE"))
    }

    @Test func calendarProblemsAreExplained() {
        #expect(!Problem.calendarDenied.title.isEmpty)
        #expect(!Problem.calendarDenied.message.isEmpty)
        #expect(!Problem.calendarDenied.symbol.isEmpty)
        #expect(Format.files(1) == "1 file")
        #expect(Format.files(3) == "3 files")
    }
}
