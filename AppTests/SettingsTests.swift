import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// A `UserDefaults` of its own, emptied when the test is done.
private final class ScratchDefaults {
    let name = "dev.camminady.gcpapi-sync.tests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name) ?? .standard
    }

    deinit {
        UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
    }
}

@Suite struct SettingsTests {
    @Test func missingValuesTakeTheirDefaults() throws {
        let decoded = try JSONDecoder().decode(
            Settings.self, from: Data(#"{"density": "dense", "unknown": 1}"#.utf8))
        var expected = Settings()
        expected.density = .dense
        #expect(decoded == expected)
        let broken = try JSONDecoder().decode(
            Settings.self, from: Data(#"{"units": "furlongs", "detailDays": "many"}"#.utf8))
        #expect(broken == Settings())
        let analysis = try JSONDecoder().decode(
            AnalysisSettings.self, from: Data(#"{"fatigueDays": 10}"#.utf8))
        #expect(analysis.fatigueDays == 10)
        #expect(analysis.fitnessDays == AnalysisSettings().fitnessDays)
    }

    @Test func settingsRoundTrip() throws {
        var settings = Settings()
        settings.units = .imperial
        settings.weekStart = .sunday
        settings.hiddenTiles = ["steps"]
        settings.routeColoring = .sport
        settings.mapStyle = .satellite
        settings.analysis.hardShare = 0.3
        settings.theme = .soft
        settings.colors = ["sport.running": "FF0000FF"]
        settings.exportsToCalendar = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
    }

    @Test func preferencesAreSavedAndRestored() {
        let scratch = ScratchDefaults()
        let preferences = Preferences(defaults: scratch.defaults)
        #expect(preferences.settings == Settings())
        preferences.settings.density = .dense
        preferences.settings.units = .metric
        preferences.settings.weekStart = .monday
        #expect(preferences.isDense)
        let restored = Preferences(defaults: scratch.defaults)
        #expect(restored.settings == preferences.settings)
        #expect(scratch.defaults.string(forKey: Preferences.unitsKey) == "metric")
        #expect(scratch.defaults.string(forKey: Preferences.weekStartKey) == "monday")
    }

    @Test func colorsCanBeChangedAndReset() {
        let scratch = ScratchDefaults()
        let preferences = Preferences(defaults: scratch.defaults)
        let role = ColorRole.sport(.cycling)
        #expect(!preferences.isCustom(role))
        preferences.setColor(Color(red: 1, green: 0, blue: 0), for: role)
        #expect(preferences.isCustom(role))
        #expect(preferences.settings.colors[role.key] == "FF0000FF")
        #expect(preferences.color(role).hex == "FF0000FF")
        preferences.setColor(nil, for: role)
        #expect(!preferences.isCustom(role))
        // A saved color that cannot be read falls back to the default.
        preferences.settings.colors[role.key] = "not a color"
        #expect(preferences.color(role).hex == role.defaultColor.hex)
    }

    @Test func hexColors() {
        #expect(Color(hex: "336699")?.hex == "336699FF")
        #expect(Color(hex: "33669980")?.hex == "33669980")
        #expect(Color(hex: "12345") == nil)
        #expect(Color(hex: "GGGGGG") == nil)
    }

    @Test func everyColorRoleHasItsOwnKey() {
        let roles = ColorRole.Group.allCases.flatMap(\.roles)
        #expect(Set(roles.map(\.key)).count == roles.count)
        #expect(roles.count == 45)
        for role in roles {
            #expect(!role.title.isEmpty)
            _ = role.defaultColor
        }
        for group in ColorRole.Group.allCases {
            #expect(!group.title.isEmpty)
        }
        #expect(ColorRole.zone(9).hue == ColorRole.zone(6).hue)
        #expect(ColorRole.accent.hue == nil)
    }

    @Test(arguments: ColorTheme.allCases)
    func everyThemeColorsEveryHue(theme: ColorTheme) {
        #expect(!theme.title.isEmpty)
        let colors = Hue.allCases.map { theme.color($0).hex }
        #expect(Set(colors).count == colors.count)
    }

    @Test func sameThingsShareAColor() {
        #expect(OverviewMetric.sleepScore.metric == .sleep)
        for line in OverviewMetric.allCases {
            #expect(line.color.hex == line.metric.tint.hex)
        }
        #expect(ColorRole.measure(.heartRate).hue == ColorRole.metric(.restingHeartRate).hue)
        // The metrics, like the sports, never share a hue.
        #expect(Set(Metric.allCases.map(\.hue)).count == Metric.allCases.count)
        #expect(Set(Sport.allCases.map(\.hue)).count == Sport.allCases.count)
    }

    @Test(
        arguments: [
            (10, ColorRole.StressLevel.rest), (25, .rest), (26, .low), (50, .low), (51, .medium),
            (75, .medium), (76, .high),
        ] as [(Int, ColorRole.StressLevel)])
    func stressBands(level: Int, band: ColorRole.StressLevel) {
        #expect(ColorRole.StressLevel(level: level) == band)
        #expect(!band.title.isEmpty)
    }

    @Test func unitsAndWeekStarts() {
        let germany = Locale(identifier: "de_DE")
        let unitedStates = Locale(identifier: "en_US")
        #expect(!Format.usesMiles(units: nil, locale: germany))
        #expect(Format.usesMiles(units: nil, locale: unitedStates))
        #expect(Format.usesMiles(units: "imperial", locale: germany))
        #expect(!Format.usesMiles(units: "metric", locale: unitedStates))
        #expect(Calendar.app(weekStart: "monday").firstWeekday == 2)
        #expect(Calendar.app(weekStart: "sunday").firstWeekday == 1)
        #expect(Calendar.app(weekStart: nil).firstWeekday == Calendar.current.firstWeekday)
    }
}

@Suite struct AnalysisSettingsTests {
    private let first = GarminDate.day("2026-10-01")

    @Test func fitnessAndFatigueWindowsAreConfigurable() throws {
        let workout = try #require(
            Workout(
                SummarizedActivity(
                    activityId: 1,
                    startTimeLocal: (try? GarminTime(hour: 7)).map {
                        LocalDateTime(date: first, time: $0)
                    },
                    duration: 60, activityTrainingLoad: 60)))
        let day = try #require(
            TrainingLoad.days(
                [workout], from: first, through: first, fitnessDays: 30, fatigueDays: 5
            ).first)
        #expect(day.fitness == 2)
        #expect(day.fatigue == 12)
    }

    @Test func recoveryUsesTheChosenShareAndWindow() {
        let end = GarminDate.day("2026-10-29")
        let data = TrainingData.sample(endingOn: end)
        let history = HealthHistory.sample(endingOn: end, days: data.loadHistory.count)
        let usual = RecoveryResponse(history: history, loads: data.loadHistory)
        let broad = RecoveryResponse(
            history: history, loads: data.loadHistory, hardShare: 0.4, baselineDays: 14)
        #expect(usual.hardShare == 0.2)
        #expect(usual.baselineDays == 28)
        #expect(broad.baselineDays == 14)
        #expect(broad.hardDays >= usual.hardDays)
        #expect(RecoveryDetailView.method(of: broad).contains("14"))
    }

    @Test func theModelPassesItsAnalysisSettings() async {
        let seen = Seen()
        let end = GarminDate.day("2026-10-29")
        let model = TrainingModel(
            today: { end },
            fetch: { end, analysis in
                await seen.record(analysis)
                return .sample(endingOn: end)
            },
            fetchHealth: { end, days in .sample(endingOn: end, days: days) })
        var analysis = AnalysisSettings()
        analysis.fitnessDays = 63
        model.analysis = analysis
        await model.load()
        #expect(await seen.values == [analysis])
    }
}

/// Records what a closure was called with.
private actor Seen {
    var values: [AnalysisSettings] = []

    func record(_ value: AnalysisSettings) {
        values.append(value)
    }
}

@Suite struct LapsAndSplitsTests {
    private let start = FITActivity.epoch.addingTimeInterval(1_000_000_000)

    private func track(laps: [FITActivity.Lap]) -> ActivityTrack {
        let records = (0...500).map { second in
            FITActivity.Record(
                time: start.addingTimeInterval(Double(second)), distance: 4 * Double(second),
                speed: 4)
        }
        return ActivityTrack(
            FITActivity(records: records, laps: laps), sport: .running, splitLength: 1000)
    }

    @Test func automaticLapsRepeatTheSplits() {
        let automatic = (0..<2).map { index in
            FITActivity.Lap(
                start: start.addingTimeInterval(Double(index) * 250), elapsed: 250, moving: 250,
                distance: 1000)
        }
        #expect(track(laps: automatic).lapsRepeatSplits)
        let manual = [
            FITActivity.Lap(start: start, elapsed: 400, moving: 400, distance: 1600),
            FITActivity.Lap(start: start, elapsed: 100, moving: 100, distance: 400),
        ]
        #expect(!track(laps: manual).lapsRepeatSplits)
        #expect(!track(laps: [FITActivity.Lap(), FITActivity.Lap()]).lapsRepeatSplits)
        #expect(!track(laps: []).lapsRepeatSplits)
    }
}
