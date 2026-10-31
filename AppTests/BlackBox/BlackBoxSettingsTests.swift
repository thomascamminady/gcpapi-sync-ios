import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Decoding settings: missing and invalid values take their defaults.
@Suite struct BlackBoxSettingsTests {
    nonisolated private static let keys: Set<String> = [
        "units", "weekStart", "density", "hiddenTiles", "showsTrends", "detailDays",
        "routeColoring", "mapStyle", "hiddenCharts", "analysis", "theme", "colors",
        "exportsToCalendar",
        "refreshesInBackground", "colormap", "reversesColormap", "shadesMonths",
    ]

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    private func roundTrip(_ settings: Settings) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    }

    /// Settings that differ from the defaults in every value.
    private var changed: Settings {
        var settings = Settings()
        settings.units = .imperial
        settings.weekStart = .sunday
        settings.density = settings.density == .dense ? .comfortable : .dense
        settings.hiddenTiles = [Metric.steps.rawValue, Metric.hrv.rawValue]
        settings.showsTrends.toggle()
        settings.detailDays = settings.detailDays == 90 ? 7 : 90
        settings.routeColoring = settings.routeColoring == .sport ? .heartRateZone : .sport
        settings.mapStyle = settings.mapStyle == .satellite ? .hybrid : .satellite
        settings.hiddenCharts = [TrackMeasure.power.rawValue]
        settings.analysis.fitnessDays = 30
        settings.analysis.fatigueDays = 5
        settings.analysis.hardShare = 0.3
        settings.analysis.baselineDays = 21
        settings.theme = settings.theme == .soft ? .vivid : .soft
        settings.colors = [ColorRole.accent.key: "112233FF"]
        settings.exportsToCalendar.toggle()
        return settings
    }

    // MARK: - Defaults

    @Test func defaultsFollowTheRegionAndHideNothing() {
        let settings = Settings()
        #expect(settings.units == .automatic)
        #expect(settings.weekStart == .automatic)
        #expect(settings.hiddenTiles.isEmpty)
        #expect(settings.hiddenCharts.isEmpty)
        #expect(settings.colors.isEmpty)
        #expect([7, 30, 90].contains(settings.detailDays))
        #expect(settings.analysis == AnalysisSettings())
    }

    @Test func analysisDefaultsAreTheDocumentedOnes() {
        let analysis = AnalysisSettings()
        #expect(analysis.fitnessDays == TrainingLoad.fitnessDays)
        #expect(analysis.fatigueDays == TrainingLoad.fatigueDays)
        #expect(analysis.hardShare == RecoveryResponse.hardShare)
        #expect(analysis.baselineDays == RecoveryResponse.baselineDays)
        // About six weeks, about one week, and the 28 days before an event.
        #expect(TrainingLoad.fitnessDays == 42)
        #expect(TrainingLoad.fatigueDays == 7)
        #expect(RecoveryResponse.baselineDays == 28)
        #expect(analysis.hardShare > 0 && analysis.hardShare < 1)
    }

    // MARK: - Encoding

    @Test func everySettingIsEncodedUnderItsName() throws {
        let data = try JSONEncoder().encode(Settings())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Self.keys)
    }

    @Test func defaultsRoundTrip() throws {
        #expect(try roundTrip(Settings()) == Settings())
        #expect(try roundTrip(changed) == changed)
        #expect(changed != Settings())
    }

    @Test func analysisRoundTrips() throws {
        let analysis = changed.analysis
        let data = try JSONEncoder().encode(analysis)
        #expect(try JSONDecoder().decode(AnalysisSettings.self, from: data) == analysis)
    }

    @Test(arguments: Settings.Units.allCases)
    func unitsRoundTrip(units: Settings.Units) throws {
        var settings = Settings()
        settings.units = units
        #expect(try roundTrip(settings).units == units)
        #expect(Settings.Units(rawValue: units.rawValue) == units)
    }

    @Test func enumRawValuesAreDistinct() {
        #expect(Set(Settings.Units.allCases.map(\.rawValue)).count == 3)
        #expect(Set(Settings.WeekStart.allCases.map(\.rawValue)).count == 3)
        #expect(Set(Settings.Density.allCases.map(\.rawValue)).count == 2)
        #expect(Set(Settings.RouteColoring.allCases.map(\.rawValue)).count == 3)
        #expect(Set(Settings.MapStyle.allCases.map(\.rawValue)).count == 3)
    }

    // MARK: - Missing values

    @Test func anEmptyObjectIsTheDefaults() throws {
        #expect(try decode("{}") == Settings())
        #expect(
            try JSONDecoder().decode(AnalysisSettings.self, from: Data("{}".utf8))
                == AnalysisSettings())
    }

    @Test func aMissingSettingNeverResetsTheOthers() throws {
        let full = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed))
        let object = try #require(full as? [String: Any])
        for key in object.keys {
            var partial = object
            partial.removeValue(forKey: key)
            let data = try JSONSerialization.data(withJSONObject: partial)
            let decoded = try JSONDecoder().decode(Settings.self, from: data)
            var expected = changed
            reset(key, of: &expected)
            #expect(decoded == expected, "without \(key)")
        }
    }

    /// Set the setting encoded under `key` to its default.
    private func reset(_ key: String, of settings: inout Settings) {
        let defaults = Settings()
        switch key {
        case "units": settings.units = defaults.units
        case "weekStart": settings.weekStart = defaults.weekStart
        case "density": settings.density = defaults.density
        case "hiddenTiles": settings.hiddenTiles = defaults.hiddenTiles
        case "showsTrends": settings.showsTrends = defaults.showsTrends
        case "detailDays": settings.detailDays = defaults.detailDays
        case "routeColoring": settings.routeColoring = defaults.routeColoring
        case "mapStyle": settings.mapStyle = defaults.mapStyle
        case "hiddenCharts": settings.hiddenCharts = defaults.hiddenCharts
        case "analysis": settings.analysis = defaults.analysis
        case "theme": settings.theme = defaults.theme
        case "colors": settings.colors = defaults.colors
        case "exportsToCalendar": settings.exportsToCalendar = defaults.exportsToCalendar
        case "refreshesInBackground":
            settings.refreshesInBackground = defaults.refreshesInBackground
        case "colormap": settings.colormap = defaults.colormap
        case "reversesColormap": settings.reversesColormap = defaults.reversesColormap
        case "shadesMonths": settings.shadesMonths = defaults.shadesMonths
        default: Issue.record("unknown key \(key)")
        }
    }

    @Test func aPartialObjectKeepsWhatItHas() throws {
        let settings = try decode(#"{"units": "imperial", "analysis": {"fitnessDays": 30}}"#)
        #expect(settings.units == .imperial)
        #expect(settings.analysis.fitnessDays == 30)
        #expect(settings.analysis.fatigueDays == AnalysisSettings().fatigueDays)
        #expect(settings.analysis.hardShare == AnalysisSettings().hardShare)
        #expect(settings.weekStart == Settings().weekStart)
        #expect(settings.theme == Settings().theme)
    }

    @Test func extraKeysAreIgnored() throws {
        let settings = try decode(#"{"weekStart": "sunday", "futureSetting": [1, 2, 3]}"#)
        #expect(settings.weekStart == .sunday)
    }

    // MARK: - Invalid values

    @Test(arguments: [
        #"{"units": "furlongs", "weekStart": "sunday"}"#,
        #"{"units": 5, "weekStart": "sunday"}"#,
        #"{"units": null, "weekStart": "sunday"}"#,
        #"{"density": "cramped", "weekStart": "sunday"}"#,
        #"{"theme": "neon", "weekStart": "sunday"}"#,
        #"{"mapStyle": ["standard"], "weekStart": "sunday"}"#,
        #"{"routeColoring": "rainbow", "weekStart": "sunday"}"#,
        #"{"hiddenTiles": "steps", "weekStart": "sunday"}"#,
        #"{"showsTrends": "yes", "weekStart": "sunday"}"#,
        #"{"detailDays": "thirty", "weekStart": "sunday"}"#,
        #"{"colors": ["FF0000FF"], "weekStart": "sunday"}"#,
        #"{"analysis": "strict", "weekStart": "sunday"}"#,
        #"{"exportsToCalendar": 2, "weekStart": "sunday"}"#,
    ])
    func anInvalidSettingTakesItsDefaultAndKeepsTheOthers(json: String) throws {
        let settings = try decode(json)
        #expect(settings.weekStart == .sunday)
        var expected = Settings()
        expected.weekStart = .sunday
        #expect(settings == expected)
    }

    @Test func anInvalidAnalysisValueKeepsTheOtherParameters() throws {
        let json = #"{"analysis": {"fitnessDays": "long", "fatigueDays": 5}}"#
        let analysis = try decode(json).analysis
        #expect(analysis.fitnessDays == AnalysisSettings().fitnessDays)
        #expect(analysis.fatigueDays == 5)
    }

    @Test(arguments: [7, 30, 90])
    func validDetailDaysAreKept(days: Int) throws {
        #expect(try decode(#"{"detailDays": \#(days)}"#).detailDays == days)
    }

    @Test(arguments: ["", "not json", "[]", "42", #"{"units": "imperial""#])
    func corruptedDataIsNotSettings(json: String) {
        #expect(throws: (any Error).self) { try decode(json) }
    }
}

/// Settings saved in an injected `UserDefaults`.
@Suite struct BlackBoxPreferencesTests {
    @Test func freshDefaultsGiveTheDefaultSettings() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        #expect(preferences.settings == Settings())
        #expect(!preferences.isDense || Settings().density == .dense)
    }

    @Test func settingsPersistAcrossInstances() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        preferences.settings.units = .imperial
        preferences.settings.hiddenTiles = [Metric.stress.rawValue]
        preferences.settings.analysis.baselineDays = 14
        preferences.settings.theme = .vivid
        let reloaded = Preferences(defaults: suite.defaults)
        #expect(reloaded.settings == preferences.settings)
        #expect(reloaded.settings.units == .imperial)
        #expect(reloaded.settings.analysis.baselineDays == 14)
    }

    @Test func instancesWithOtherDefaultsAreIndependent() throws {
        let first = try BlackBoxDefaults()
        let second = try BlackBoxDefaults()
        let preferences = Preferences(defaults: first.defaults)
        preferences.settings.weekStart = .sunday
        #expect(Preferences(defaults: second.defaults).settings == Settings())
    }

    @Test(arguments: Settings.Units.allCases)
    func unitsAreSavedForCodeAwayFromTheMainActor(units: Settings.Units) throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        preferences.settings.units = units
        let saved = suite.defaults.string(forKey: Preferences.unitsKey)
        // Automatic may also be saved as no choice at all.
        #expect(saved == units.rawValue || (units == .automatic && saved == nil))
    }

    @Test(arguments: Settings.WeekStart.allCases)
    func weekStartIsSavedForCodeAwayFromTheMainActor(weekStart: Settings.WeekStart) throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        preferences.settings.weekStart = weekStart
        let saved = suite.defaults.string(forKey: Preferences.weekStartKey)
        #expect(saved == weekStart.rawValue || (weekStart == .automatic && saved == nil))
    }

    @Test func corruptedStorageFallsBackToTheDefaults() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        preferences.settings.units = .metric
        preferences.settings.showsTrends.toggle()
        let keys = suite.storedKeys.subtracting([Preferences.unitsKey, Preferences.weekStartKey])
        let key = try #require(keys.first, "\(suite.storedKeys)")
        let garbage: [Any] = [Data("{not json".utf8), "garbage", 42, ["a": 1]]
        for value in garbage {
            suite.defaults.set(value, forKey: key)
            let settings = Preferences(defaults: suite.defaults).settings
            #expect(settings.showsTrends == Settings().showsTrends, "\(value)")
            #expect(settings.hiddenTiles.isEmpty, "\(value)")
        }
    }

    @Test func storedSettingsFromAnOlderVersionKeepTheirValues() throws {
        let suite = try BlackBoxDefaults()
        Preferences(defaults: suite.defaults).settings.density = .dense
        let keys = suite.storedKeys.subtracting([Preferences.unitsKey, Preferences.weekStartKey])
        let key = try #require(keys.first)
        let stored = try #require(suite.defaults.data(forKey: key))
        #expect(try JSONDecoder().decode(Settings.self, from: stored).density == .dense)
        // An older version knew only some of the settings.
        suite.defaults.set(Data(#"{"weekStart": "sunday"}"#.utf8), forKey: key)
        let settings = Preferences(defaults: suite.defaults).settings
        #expect(settings.weekStart == .sunday)
        #expect(settings.units == Settings().units)
    }

    @Test func denseFollowsTheDensity() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        preferences.settings.density = .dense
        #expect(preferences.isDense)
        preferences.settings.density = .comfortable
        #expect(!preferences.isDense)
    }
}
