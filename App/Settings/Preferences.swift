import Foundation
import Observation
import SwiftUI
import UIKit

/// Everything the user can configure. Missing values (from older versions) take their
/// defaults, so adding a setting never resets the others.
nonisolated struct Settings: Codable, Equatable, Sendable {
    enum Units: String, Codable, CaseIterable, Sendable {
        case automatic
        case metric
        case imperial
    }

    enum WeekStart: String, Codable, CaseIterable, Sendable {
        case automatic
        case monday
        case sunday
    }

    enum Density: String, Codable, CaseIterable, Sendable {
        case comfortable
        case dense
    }

    enum RouteColoring: String, Codable, CaseIterable, Sendable {
        case heartRateZone = "heart_rate_zone"
        /// Heart rate on the color map, from the activity's lowest to its highest.
        case heartRate = "heart_rate"
        case sport
    }

    enum MapStyle: String, Codable, CaseIterable, Sendable {
        case standard
        case hybrid
        case satellite
    }

    var units = Units.automatic
    var weekStart = WeekStart.automatic
    var density = Density.comfortable
    /// Summary tiles not shown, by metric.
    var hiddenTiles: Set<String> = []
    var showsTrends = true
    /// Days the detail screens open with: 7, 30 or 90.
    var detailDays = 7
    var routeColoring = RouteColoring.heartRateZone
    var mapStyle = MapStyle.standard
    /// Activity charts not shown, by measure.
    var hiddenCharts: Set<String> = []
    var analysis = AnalysisSettings()
    var theme = ColorTheme.okabeIto
    /// The color map for coloring by value.
    var colormap = Colormap.viridis
    var reversesColormap = false
    /// Whether the dashboard's months shade their figures by value.
    var shadesMonths = true
    /// Colors chosen instead of the theme's, as `RRGGBBAA` by color role.
    var colors: [String: String] = [:]
    var exportsToCalendar = false
    var refreshesInBackground = true

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        func value<Value: Decodable>(_ key: CodingKeys, _ fallback: Value) -> Value {
            (try? container.decodeIfPresent(Value.self, forKey: key)) ?? fallback
        }
        units = value(.units, defaults.units)
        weekStart = value(.weekStart, defaults.weekStart)
        density = value(.density, defaults.density)
        hiddenTiles = value(.hiddenTiles, defaults.hiddenTiles)
        showsTrends = value(.showsTrends, defaults.showsTrends)
        detailDays = value(.detailDays, defaults.detailDays)
        if ![7, 30, 90].contains(detailDays) {
            detailDays = defaults.detailDays
        }
        routeColoring = value(.routeColoring, defaults.routeColoring)
        mapStyle = value(.mapStyle, defaults.mapStyle)
        hiddenCharts = value(.hiddenCharts, defaults.hiddenCharts)
        analysis = value(.analysis, defaults.analysis)
        theme = value(.theme, defaults.theme)
        colormap = value(.colormap, defaults.colormap)
        reversesColormap = value(.reversesColormap, defaults.reversesColormap)
        shadesMonths = value(.shadesMonths, defaults.shadesMonths)
        colors = value(.colors, defaults.colors)
        exportsToCalendar = value(.exportsToCalendar, defaults.exportsToCalendar)
        refreshesInBackground = value(.refreshesInBackground, defaults.refreshesInBackground)
    }
}

/// The parameters of the training analyses.
nonisolated struct AnalysisSettings: Codable, Equatable, Sendable {
    /// Days fitness and fatigue average over.
    var fitnessDays = 42.0
    var fatigueDays = 7.0
    /// The share of training days, by load, that count as hard.
    var hardShare = 0.2
    /// Days before a hard day whose median is the usual level.
    var baselineDays = 28

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        fitnessDays =
            (try? container.decodeIfPresent(Double.self, forKey: .fitnessDays))
            ?? defaults.fitnessDays
        fatigueDays =
            (try? container.decodeIfPresent(Double.self, forKey: .fatigueDays))
            ?? defaults.fatigueDays
        hardShare =
            (try? container.decodeIfPresent(Double.self, forKey: .hardShare)) ?? defaults.hardShare
        baselineDays =
            (try? container.decodeIfPresent(Int.self, forKey: .baselineDays))
            ?? defaults.baselineDays
    }
}

/// The user's settings, saved in `UserDefaults` whenever they change.
@Observable
final class Preferences {
    /// The app's settings; views and colors read them from here.
    static let shared = Preferences()

    /// Keys of the settings that code away from the main actor reads directly.
    nonisolated static let unitsKey = "units"
    nonisolated static let weekStartKey = "weekStart"
    private static let settingsKey = "settings"
    /// The key of when the settings last changed, for syncing.
    nonisolated static let modifiedKey = "settingsModified"

    var settings: Settings {
        didSet {
            if !isAdopting {
                modified = .now
            }
            save()
        }
    }

    /// When the settings last changed here, or on the device they were adopted from.
    private(set) var modified: Date
    private var isAdopting = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings =
            defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
        modified = defaults.object(forKey: Self.modifiedKey) as? Date ?? .distantPast
    }

    /// Take `shared` settings, changed at `modified` on another device, keeping what belongs
    /// to this one: the calendar, which needs its permission, and background refresh.
    func adopt(_ shared: Settings, modified: Date) {
        var adopted = shared
        adopted.exportsToCalendar = settings.exportsToCalendar
        adopted.refreshesInBackground = settings.refreshesInBackground
        isAdopting = true
        settings = adopted
        isAdopting = false
        self.modified = modified
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        defaults.set(modified, forKey: Self.modifiedKey)
        defaults.set(settings.units.rawValue, forKey: Self.unitsKey)
        defaults.set(settings.weekStart.rawValue, forKey: Self.weekStartKey)
    }

    /// The color of `role`: the user's choice, or the color of their theme.
    func color(_ role: ColorRole) -> Color {
        if let chosen = settings.colors[role.key].flatMap(Color.init(hex:)) {
            return chosen
        }
        return role.hue.map(settings.theme.color) ?? Color(.accent)
    }

    /// Use `color` for `role`, or the default again with `nil`.
    func setColor(_ color: Color?, for role: ColorRole) {
        settings.colors[role.key] = color.map(\.hex)
    }

    /// Whether `role` has a color of the user's own.
    func isCustom(_ role: ColorRole) -> Bool {
        settings.colors[role.key] != nil
    }

    var isDense: Bool { settings.density == .dense }
}

extension Calendar {
    /// The current calendar, starting weeks on the day the user chose.
    nonisolated static var app: Calendar {
        app(weekStart: UserDefaults.standard.string(forKey: Preferences.weekStartKey))
    }

    /// The current calendar with weeks starting as `weekStart`, a ``Settings/WeekStart`` raw
    /// value, says.
    nonisolated static func app(weekStart: String?) -> Calendar {
        var calendar = Self.current
        switch weekStart {
        case Settings.WeekStart.monday.rawValue: calendar.firstWeekday = 2
        case Settings.WeekStart.sunday.rawValue: calendar.firstWeekday = 1
        default: break
        }
        return calendar
    }
}

extension Color {
    /// A color from `RRGGBB` or `RRGGBBAA`.
    nonisolated init?(hex: String) {
        guard [6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit),
            let value = UInt64(hex, radix: 16)
        else { return nil }
        let rgba = hex.count == 6 ? value << 8 | 0xFF : value
        self.init(
            red: Double(rgba >> 24 & 0xFF) / 255, green: Double(rgba >> 16 & 0xFF) / 255,
            blue: Double(rgba >> 8 & 0xFF) / 255, opacity: Double(rgba & 0xFF) / 255)
    }

    /// `RRGGBBAA`, in the current appearance.
    var hex: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue, alpha]
            .map { String(format: "%02X", Int((max(0, min(1, $0)) * 255).rounded())) }
            .joined()
    }
}
