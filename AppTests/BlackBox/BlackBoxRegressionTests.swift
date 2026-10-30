import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// Behavior of `Format` that contradicts its documentation.
@Suite struct FormatBlackBoxRegressions {
    @Test func distanceDecimalsFollowTheDocumentedRule() {
        let text = Format.distance(metres: 10_200)
        // Two decimals below 10 (6.34 mi), one from 10 on (10.2 km).
        if Format.usesMiles {
            #expect(text.hasSuffix(" mi"))
            #expect(BlackBox.digits(text) == "634", "\(text)")
        } else {
            #expect(text.hasSuffix(" km"))
            #expect(BlackBox.digits(text) == "102", "\(text)")
        }
    }

    @Test func marathonDistanceHasOneDecimal() {
        let text = Format.distance(metres: 42_195)
        #expect(BlackBox.digits(text) == (Format.usesMiles ? "262" : "422"), "\(text)")
    }
}

/// `Color(hex:)` accepting text that is not `RRGGBB` or `RRGGBBAA`.
@Suite struct HexColorBlackBoxRegressions {
    /// A sign is not a hexadecimal digit, even where integer parsing accepts one.
    @Test(arguments: ["+FFFFF", "-00000", "+0000000", "-0000000"])
    func signedHexIsNoColor(text: String) {
        #expect(Color(hex: text) == nil, "\(text)")
    }
}

/// `Preferences` and `Settings` behavior that contradicts their documentation.
@Suite struct PreferencesBlackBoxRegressions {
    @Test(arguments: ColorTheme.allCases)
    func changingTheThemeRecolorsEveryRole(theme: ColorTheme) throws {
        let suite = try BlackBoxDefaults()
        let preferences = Preferences(defaults: suite.defaults)
        preferences.settings.theme = theme
        for role in BlackBox.expectedRoles {
            if let hue = role.hue {
                #expect(preferences.color(role).hex == theme.color(hue).hex, "\(role)")
            }
        }
    }

    @Test(arguments: [45, 0, -7, 365])
    func detailDaysAreSevenThirtyOrNinety(days: Int) throws {
        let settings = try decode(#"{"detailDays": \#(days)}"#)
        #expect([7, 30, 90].contains(settings.detailDays))
    }

    private func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }
}

/// `Session` behavior that contradicts its documentation.
@Suite struct SessionBlackBoxRegressions {
    @Test func connectingEndsTheDemo() async throws {
        let scratch = ScratchKeychain()
        let session = Session(keychain: scratch.store, transport: garmin())
        session.startDemo()
        #expect(session.isDemo)
        try await session.connect(apiKey: "good-key")
        let signedIn = session.isSignedIn
        let demo = session.isDemo
        #expect(signedIn)
        #expect(demo == false)
    }
}

/// Where the demo answers differently from Garmin.
@Suite struct DemoTransportBlackBoxRegressions {
    private let end = BlackBox.today

    private func demo() throws -> GarminClient {
        try client(DemoTransport(), apiKey: "demo-key")
    }

    private func range(_ first: GarminDate, _ last: GarminDate) -> ActivityFilters {
        ActivityFilters(startDate: first, endDate: last)
    }

    @Test func activitiesAreNewestFirst() async throws {
        let activities = try await demo().searchActivities(
            start: 0, limit: 200, filters: range(end.adding(days: -27), end))
        let starts = activities.compactMap(\.startTimeLocal)
        #expect(starts == starts.sorted(by: >))
    }
}
