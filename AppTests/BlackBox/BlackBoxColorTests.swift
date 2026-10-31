import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Everything the app colors, the themes, and colors as `RRGGBBAA`.
@Suite struct BlackBoxColorRoleTests {
    @Test func everyRoleIsConfigurableInExactlyOneGroup() {
        let listed = BlackBox.listedRoles
        let expected = BlackBox.expectedRoles
        #expect(Set(listed) == Set(expected))
        #expect(listed.count == Set(listed).count)
        #expect(listed.count == expected.count)
    }

    @Test func keysAndIdsAreUniqueAndStable() {
        let roles = BlackBox.expectedRoles
        let keys = roles.map(\.key)
        #expect(Set(keys).count == roles.count)
        #expect(Set(roles.map(\.id)).count == roles.count)
        #expect(keys.allSatisfy { !$0.isEmpty })
        // Equal roles built separately share their key.
        #expect(BlackBox.expectedRoles.map(\.key) == keys)
        #expect(ColorRole.metric(.steps).key == ColorRole.metric(Metric.allCases[0]).key)
        #expect(ColorRole.zone(3).key != ColorRole.zone(4).key)
    }

    @Test func groupsAreTitledAndNotEmpty() {
        for group in ColorRole.Group.allCases {
            #expect(!group.title.isEmpty, "\(group)")
            #expect(!group.roles.isEmpty, "\(group)")
            #expect(group.id == group)
            let titles = group.roles.map(\.title)
            #expect(titles.allSatisfy { !$0.isEmpty }, "\(group)")
            #expect(Set(titles).count == titles.count, "\(group): \(titles)")
        }
        #expect(Set(ColorRole.Group.allCases.map(\.title)).count == ColorRole.Group.allCases.count)
    }

    @Test func groupsHoldWhatTheirNamesSay() {
        #expect(ColorRole.Group.app.roles.contains(.accent))
        #expect(Set(ColorRole.Group.health.roles) == Set(Metric.allCases.map(ColorRole.metric)))
        #expect(
            Set(ColorRole.Group.sleep.roles) == Set(SleepStage.allCases.map(ColorRole.sleepStage))
        )
        #expect(
            Set(ColorRole.Group.stress.roles)
                == Set(ColorRole.StressLevel.allCases.map(ColorRole.stress))
        )
        #expect(
            Set(ColorRole.Group.status.roles)
                == Set(ColorRole.Status.allCases.map(ColorRole.status))
        )
        #expect(Set(ColorRole.Group.sports.roles) == Set(Sport.allCases.map(ColorRole.sport)))
        #expect(ColorRole.Group.zones.roles == (0...6).map(ColorRole.zone))
        #expect(
            Set(ColorRole.Group.activity.roles)
                == Set(TrackMeasure.allCases.map(ColorRole.measure))
        )
        let training = Set(ColorRole.Group.training.roles)
        #expect(training.isSuperset(of: [.fitness, .fatigue]))
        #expect(training.isSuperset(of: FormZone.allCases.map(ColorRole.form)))
    }

    @Test(arguments: 0...6)
    func zonesAreNumberedFromOne(index: Int) {
        #expect(ColorRole.zone(index).title.contains("\(index + 1)"))
    }

    @Test func zoneStyleHasTheSevenZoneColors() {
        #expect(ZoneStyle.colors.map(\.hex) == (0...6).map { ColorRole.zone($0).color.hex })
    }

    @Test func theSameThingHasTheSameHueEverywhere() {
        for metric in Metric.allCases {
            #expect(ColorRole.metric(metric).hue == metric.hue, "\(metric)")
        }
        for sport in Sport.allCases {
            #expect(ColorRole.sport(sport).hue == sport.hue, "\(sport)")
            #expect(sport.color.hex == ColorRole.sport(sport).color.hex, "\(sport)")
        }
        for stage in SleepStage.allCases {
            #expect(ColorRole.sleepStage(stage).hue == stage.hue, "\(stage)")
            #expect(stage.color.hex == ColorRole.sleepStage(stage).color.hex, "\(stage)")
        }
        for zone in FormZone.allCases {
            #expect(ColorRole.form(zone).hue == zone.hue, "\(zone)")
            #expect(zone.color.hex == ColorRole.form(zone).color.hex, "\(zone)")
        }
        for measure in TrackMeasure.allCases {
            #expect(ColorRole.measure(measure).hue == measure.hue, "\(measure)")
            #expect(measure.color.hex == ColorRole.measure(measure).color.hex, "\(measure)")
        }
    }

    @Test func formZonesAreColoredLikeStatuses() {
        let hues = FormZone.allCases.map(\.hue)
        #expect(hues == [.amber, .blue, .gray, .green, .red])
        #expect(ColorRole.status(.good).hue == .green)
        #expect(ColorRole.status(.fair).hue == .amber)
        #expect(ColorRole.status(.poor).hue == .red)
    }

    @Test func theAccentIsTheAppIconsAndNotATheme() {
        #expect(ColorRole.accent.hue == nil)
        #expect(!ColorRole.accent.title.isEmpty)
    }

    @Test func defaultColorsAreTheThemes() {
        let theme = Preferences.shared.settings.theme
        for role in BlackBox.expectedRoles {
            if let hue = role.hue {
                #expect(role.defaultColor.hex == theme.color(hue).hex, "\(role)")
            }
            #expect(role.color.hex == Preferences.shared.color(role).hex, "\(role)")
        }
    }

    @Test func stressLevelsAreOrdered() {
        #expect(ColorRole.StressLevel.allCases == [.rest, .low, .medium, .high])
        #expect(ColorRole.StressLevel.allCases.map(\.index) == [0, 1, 2, 3])
        #expect(ColorRole.Status.allCases == [.good, .fair, .poor])
        #expect(ColorRole.Status.allCases.map(\.index) == [0, 1, 2])
        let titles = ColorRole.StressLevel.allCases.map(\.title)
        #expect(Set(titles).count == 4 && titles.allSatisfy { !$0.isEmpty })
        let statuses = ColorRole.Status.allCases.map(\.title)
        #expect(Set(statuses).count == 3 && statuses.allSatisfy { !$0.isEmpty })
    }

    @Test func everyStressLevelFromZeroToAHundredHasABand() {
        var previous = -1
        for level in 0...100 {
            let index = ColorRole.StressLevel(level: level).index
            #expect(index >= previous, "\(level)")
            previous = index
        }
        #expect(previous == 3)
    }
}

/// Every theme colors every hue.
@Suite struct BlackBoxColorThemeTests {
    nonisolated private static let categorical: [Hue] = [
        .blue, .orange, .aqua, .amber, .magenta, .green, .violet, .red,
    ]

    @Test func themesArePresentable() {
        #expect(ColorTheme.allCases == [.okabeIto, .balanced, .vivid, .soft])
        let titles = ColorTheme.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == ColorTheme.allCases.count)
        for theme in ColorTheme.allCases {
            #expect(ColorTheme(rawValue: theme.rawValue) == theme)
        }
    }

    @Test(arguments: ColorTheme.allCases)
    func everyThemeColorsEveryHueDistinctly(theme: ColorTheme) {
        #expect(Hue.allCases.count == 12)
        let colors = Hue.allCases.map { theme.color($0).hex }
        #expect(colors.allSatisfy(BlackBox.isHex8), "\(colors)")
        #expect(Set(colors).count == Hue.allCases.count, "\(theme): \(colors)")
        #expect(colors.allSatisfy { $0.uppercased().hasSuffix("FF") }, "\(colors)")
    }

    @Test(arguments: ColorTheme.allCases)
    func categoricalHuesAreDistinct(theme: ColorTheme) {
        let colors = Self.categorical.map { theme.color($0).hex }
        #expect(Set(colors).count == Self.categorical.count)
    }

    @Test func themesDiffer() {
        let palettes = ColorTheme.allCases.map { theme in Hue.allCases.map { theme.color($0).hex } }
        #expect(Set(palettes).count == ColorTheme.allCases.count)
    }

    @Test func vividIsApplesSystemColors() {
        #expect(ColorTheme.vivid.color(.blue).hex == Color.blue.hex)
        #expect(ColorTheme.vivid.color(.orange).hex == Color.orange.hex)
        #expect(ColorTheme.vivid.color(.green).hex == Color.green.hex)
        #expect(ColorTheme.vivid.color(.red).hex == Color.red.hex)
    }

    @Test(arguments: ColorTheme.allCases)
    func themesRoundTripAsJSON(theme: ColorTheme) throws {
        let data = try JSONEncoder().encode(theme)
        #expect(try JSONDecoder().decode(ColorTheme.self, from: data) == theme)
    }
}

/// Colors chosen in the settings, saved as `RRGGBBAA`.
@Suite struct BlackBoxPreferenceColorTests {
    @Test func withoutAChoiceEveryRoleHasItsThemesColor() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        for role in BlackBox.expectedRoles {
            #expect(!preferences.isCustom(role), "\(role)")
            if let hue = role.hue {
                let expected = preferences.settings.theme.color(hue).hex
                #expect(preferences.color(role).hex == expected, "\(role)")
            }
        }
    }

    @Test(arguments: [ColorRole.accent, .metric(.hrv), .sport(.cycling), .zone(6), .fatigue])
    func aChosenColorIsUsedSavedAndForgotten(role: ColorRole) throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        let original = preferences.color(role).hex
        let chosen: Color = try #require(Color(hex: "12345678"))
        preferences.setColor(chosen, for: role)
        #expect(preferences.isCustom(role))
        #expect(preferences.color(role).hex == "12345678")
        #expect(preferences.settings.colors[role.key]?.uppercased() == "12345678")
        #expect(preferences.settings.colors.count == 1)
        let others = BlackBox.expectedRoles.filter { $0 != role }
        #expect(others.allSatisfy { !preferences.isCustom($0) })

        let reloaded = Preferences(defaults: suite.defaults)
        #expect(reloaded.isCustom(role))
        #expect(reloaded.color(role).hex == "12345678")

        preferences.setColor(nil, for: role)
        #expect(!preferences.isCustom(role))
        #expect(preferences.settings.colors[role.key] == nil)
        #expect(preferences.color(role).hex == original)
        #expect(!Preferences(defaults: suite.defaults).isCustom(role))
    }

    @Test func aChosenColorSurvivesAThemeChange() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        let chosen: Color = try #require(Color(hex: "ABCDEF"))
        preferences.setColor(chosen, for: .metric(.steps))
        preferences.settings.theme = .soft
        #expect(preferences.color(.metric(.steps)).hex == "ABCDEFFF")
    }

    @Test func anUnreadableSavedColorFallsBackToTheDefault() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        let role = ColorRole.metric(.stress)
        let expected = preferences.color(role).hex
        preferences.settings.colors[role.key] = "not a color"
        #expect(preferences.color(role).hex == expected)
    }

    @Test func savedColorsAreHex() throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        preferences.setColor(.red, for: .accent)
        preferences.setColor(.indigo, for: .zone(0))
        for value in preferences.settings.colors.values {
            #expect(BlackBox.isHex8(value), "\(value)")
            #expect(Color(hex: value) != nil)
        }
        #expect(preferences.color(.accent).hex == Color.red.hex)
    }
}

/// `Color(hex:)` and `.hex`.
@Suite struct BlackBoxHexColorTests {
    @Test(arguments: [
        ("FF0000", "FF0000FF"), ("00FF00", "00FF00FF"), ("0000FF", "0000FFFF"),
        ("000000", "000000FF"), ("FFFFFF", "FFFFFFFF"), ("11223344", "11223344"),
        ("abcdef", "ABCDEFFF"), ("aBcDeF80", "ABCDEF80"), ("00000000", "00000000"),
    ])
    func hexRoundTrips(input: String, output: String) throws {
        let color = try #require(Color(hex: input))
        #expect(color.hex.uppercased() == output)
    }

    @Test(arguments: 0...255)
    func everyChannelValueRoundTrips(value: Int) throws {
        let byte = String(format: "%02X", value)
        for text in ["\(byte)0000FF", "00\(byte)00FF", "0000\(byte)FF", "336699\(byte)"] {
            let color = try #require(Color(hex: text))
            #expect(color.hex.uppercased() == text, "\(text)")
        }
    }

    @Test(arguments: [
        "", "F", "FFF", "FFFF", "FFFFF", "FFFFFFF", "FFFFFFFFF", "FFFFFFFFFF", "GG0000",
        "0x1234", " FF0000", "FF0000 ", "FF 000", "#FF00",
        "\u{FF26}\u{FF26}0000", "\u{0661}\u{0662}\u{0663}\u{0664}\u{0665}\u{0666}", "zzzzzz",
        "12345G78",
    ])
    func invalidHexIsNoColor(text: String) {
        #expect(Color(hex: text) == nil, "\(text)")
    }

    @Test func knownColorsHaveTheirHex() {
        #expect(Color.black.hex.uppercased() == "000000FF")
        #expect(Color.white.hex.uppercased() == "FFFFFFFF")
        #expect(Color.clear.hex.uppercased().hasSuffix("00"))
        #expect(Color(red: 1, green: 0, blue: 0).hex.uppercased() == "FF0000FF")
        #expect(Color(red: 0, green: 0, blue: 1, opacity: 0.4).hex.uppercased() == "0000FF66")
        let gray = Color(red: 51 / 255, green: 102 / 255, blue: 153 / 255)
        #expect(gray.hex.uppercased() == "336699FF")
    }

    @Test func colorsOutsideSRGBStillHaveEightDigits() {
        let colors = [
            Color(.displayP3, red: 1, green: 0, blue: 0),
            Color(.sRGB, red: 1.4, green: -0.3, blue: 0.5),
            Color(.sRGBLinear, red: 0, green: 1, blue: 0, opacity: 2),
        ]
        for color in colors {
            #expect(BlackBox.isHex8(color.hex), "\(color.hex)")
        }
    }

    @Test func systemColorsRoundTripThroughHex() throws {
        for color in [Color.red, .orange, .yellow, .green, .mint, .teal, .blue, .purple] {
            let restored = try #require(Color(hex: color.hex))
            #expect(restored.hex == color.hex)
            #expect(BlackBox.isHex8(color.hex))
        }
    }

    @Test func lightAndDarkColorsResolveToOneOfTheirShades() {
        let hex = Color(light: 0x112233, dark: 0x445566).hex.uppercased()
        #expect(["112233FF", "445566FF"].contains(hex))
    }
}
