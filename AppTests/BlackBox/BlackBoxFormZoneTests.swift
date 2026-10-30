import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// Zones from the most tired to the most rested.
private let ordered: [FormZone] = [.overreaching, .productive, .neutral, .fresh, .detraining]

/// A share inside `zone`'s band, away from its edges.
private func inside(_ zone: FormZone) -> Double {
    let band = zone.band
    switch (band.lowerBound.isFinite, band.upperBound.isFinite) {
    case (true, true): return (band.lowerBound + band.upperBound) / 2
    case (false, true): return band.upperBound - 0.05
    case (true, false): return band.lowerBound + 0.05
    case (false, false): return 0
    }
}

/// Where a band edge may lie: `lowest` through `highest`, give or take rounding.
nonisolated private func edge(_ lowest: Double, _ highest: Double? = nil) -> ClosedRange<Double> {
    (lowest - 1e-12)...((highest ?? lowest) + 1e-12)
}

@Suite("Form zones")
struct BlackBoxFormZoneTests {
    @Test("Every case is a zone")
    func cases() {
        #expect(Set(FormZone.allCases) == Set(ordered))
    }

    // intervals.icu's zones go back to Joe Friel's: high risk below -30 %, optimal from -30 %
    // to -10 %, a grey zone up to +5 %, fresh above that. Where fresh ends and transition
    // begins differs between sources (+20 % or +25 %), so that edge is only bounded.
    @Test(
        "intervals.icu's zones by form as a share of fitness",
        arguments: [
            (0.40, FormZone.detraining), (0.30, .detraining), (0.18, .fresh), (0.15, .fresh),
            (0.06, .fresh), (0.04, .neutral), (0.0, .neutral), (-0.09, .neutral),
            (-0.11, .productive), (-0.20, .productive), (-0.29, .productive),
            (-0.31, .overreaching), (-0.50, .overreaching),
        ])
    func intervalsZones(share: Double, zone: FormZone) {
        #expect(FormZone(share: share) == zone)
    }

    @Test(
        "intervals.icu's zone boundaries are the band edges",
        arguments: [
            (FormZone.overreaching, nil, edge(-0.30)), (.productive, edge(-0.30), edge(-0.10)),
            (.neutral, edge(-0.10), edge(0.05)), (.fresh, edge(0.05), edge(0.20, 0.25)),
            (.detraining, edge(0.20, 0.25), nil),
        ] as [(FormZone, ClosedRange<Double>?, ClosedRange<Double>?)])
    func intervalsBands(
        zone: FormZone, lower: ClosedRange<Double>?, upper: ClosedRange<Double>?
    ) {
        if let lower {
            #expect(lower.contains(zone.band.lowerBound))
        }
        if let upper {
            #expect(upper.contains(zone.band.upperBound))
        }
    }

    @Test("Extreme shares fall into the outer zones")
    func extremes() {
        for share in [-1.0, -3.0, -1e9] {
            #expect(FormZone(share: share) == .overreaching)
        }
        for share in [1.0, 4.0, 1e9] {
            #expect(FormZone(share: share) == .detraining)
        }
    }

    @Test("A share inside a zone's band is that zone", arguments: FormZone.allCases)
    func bandMatchesZone(zone: FormZone) {
        #expect(FormZone(share: inside(zone)) == zone)
        #expect(zone.band.lowerBound < zone.band.upperBound)
    }

    @Test("The bands are ordered from tired to rested and leave no gaps")
    func bandsTile() {
        for (lower, upper) in zip(ordered, ordered.dropFirst()) {
            #expect(
                AnalyticsBlackBox.isClose(
                    lower.band.upperBound, upper.band.lowerBound, tolerance: 1e-12))
        }
    }

    @Test("More form never means a more tired zone")
    func monotone() {
        var previous = 0
        var seen: Set<FormZone> = []
        for step in -1500...1500 {
            let zone = FormZone(share: Double(step) / 1000)
            let rank = ordered.firstIndex(of: zone) ?? -1
            #expect(rank >= previous)
            previous = rank
            seen.insert(zone)
        }
        #expect(seen == Set(ordered))
    }

    @Test("Every share just inside a band edge belongs to one of the two neighbours")
    func edges() {
        for (lower, upper) in zip(ordered, ordered.dropFirst()) {
            let edge = lower.band.upperBound
            #expect(FormZone(share: edge - 1e-9) == lower)
            #expect(FormZone(share: edge + 1e-9) == upper)
            #expect([lower, upper].contains(FormZone(share: edge)))
        }
    }

    @Test("Hues like statuses: amber, blue, gray, green and red")
    func hues() {
        #expect(FormZone.detraining.hue == .amber)
        #expect(FormZone.fresh.hue == .blue)
        #expect(FormZone.neutral.hue == .gray)
        #expect(FormZone.productive.hue == .green)
        #expect(FormZone.overreaching.hue == .red)
    }

    @Test("Titles, symbols and explanations are present and tell the zones apart")
    func texts() {
        let zones = FormZone.allCases
        #expect(zones.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
        #expect(zones.allSatisfy { !$0.explanation.isEmpty })
        #expect(Set(zones.map(\.title)).count == zones.count)
        #expect(Set(zones.map(\.symbol)).count == zones.count)
        #expect(Set(zones.map(\.explanation)).count == zones.count)
    }
}

@Suite("Analysis settings")
struct BlackBoxAnalysisSettingsTests {
    @Test("The defaults are the analyses' own")
    func defaults() {
        let settings = AnalysisSettings()
        #expect(settings.fitnessDays == TrainingLoad.fitnessDays)
        #expect(settings.fatigueDays == TrainingLoad.fatigueDays)
        #expect(settings.hardShare == RecoveryResponse.hardShare)
        #expect(settings.baselineDays == RecoveryResponse.baselineDays)
        #expect(Settings().analysis == settings)
    }

    @Test("The documented recovery parameters")
    func recoveryConstants() {
        #expect(RecoveryResponse.baselineDays == 28)
        #expect(RecoveryResponse.lags == [-1, 0, 1, 2, 3])
        #expect(RecoveryResponse.hardShare > 0 && RecoveryResponse.hardShare < 1)
        #expect(RecoveryResponse.minimumEvents >= 2)
        #expect(RecoveryResponse.minimumBaseline >= 1)
        #expect(RecoveryResponse.minimumBaseline <= RecoveryResponse.baselineDays)
    }

    @Test("Settings survive encoding and decoding")
    func roundTrip() throws {
        var settings = AnalysisSettings()
        settings.fitnessDays = 30
        settings.fatigueDays = 5
        settings.hardShare = 0.35
        settings.baselineDays = 21
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AnalysisSettings.self, from: data) == settings)
    }

    @Test("Decoding an empty object gives the defaults")
    func emptyObject() throws {
        let decoded = try JSONDecoder().decode(AnalysisSettings.self, from: Data("{}".utf8))
        #expect(decoded == AnalysisSettings())
    }

    @Test("A setting missing from older data takes its default, the others are kept")
    func missingValues() throws {
        var settings = AnalysisSettings()
        settings.fitnessDays = 30
        settings.fatigueDays = 5
        settings.hardShare = 0.35
        settings.baselineDays = 21
        let data = try JSONEncoder().encode(settings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.count == 4)
        let defaults = AnalysisSettings()
        for key in object.keys {
            var partial = object
            partial.removeValue(forKey: key)
            let decoded = try JSONDecoder().decode(
                AnalysisSettings.self, from: try JSONSerialization.data(withJSONObject: partial))
            let fields: [(Double, Double, Double)] = [
                (decoded.fitnessDays, settings.fitnessDays, defaults.fitnessDays),
                (decoded.fatigueDays, settings.fatigueDays, defaults.fatigueDays),
                (decoded.hardShare, settings.hardShare, defaults.hardShare),
                (
                    Double(decoded.baselineDays), Double(settings.baselineDays),
                    Double(defaults.baselineDays)
                ),
            ]
            // Exactly one field fell back to its default.
            #expect(fields.filter { $0.0 == $0.2 && $0.0 != $0.1 }.count == 1)
            #expect(fields.filter { $0.0 == $0.1 }.count == 3)
        }
    }
}

@Suite("Sports by Garmin activity type")
struct BlackBoxSportTests {
    @Test(
        "Running types",
        arguments: [
            "running", "trail_running", "treadmill_running", "track_running", "street_running",
            "indoor_running",
        ])
    func running(key: String) {
        #expect(Sport(typeKey: key) == .running)
    }

    @Test(
        "Cycling types",
        arguments: [
            "cycling", "road_biking", "mountain_biking", "gravel_cycling", "indoor_cycling",
        ])
    func cycling(key: String) {
        #expect(Sport(typeKey: key) == .cycling)
    }

    @Test("Swimming types", arguments: ["lap_swimming", "open_water_swimming", "swimming"])
    func swimming(key: String) {
        #expect(Sport(typeKey: key) == .swimming)
    }

    @Test("Strength training", arguments: ["strength_training"])
    func strength(key: String) {
        #expect(Sport(typeKey: key) == .strength)
    }

    @Test("Walking types", arguments: ["walking", "casual_walking", "speed_walking"])
    func walking(key: String) {
        #expect(Sport(typeKey: key) == .walking)
    }

    @Test("Anything else", arguments: [nil, "", "yoga", "breathwork", "black_box_unknown"])
    func other(key: String?) {
        #expect(Sport(typeKey: key) == .other)
    }

    @Test("Every sport has a title, a symbol, its own hue and is its own id")
    func presentation() {
        let sports = Sport.allCases
        #expect(sports.count == 6)
        #expect(sports.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty && $0.id == $0 })
        #expect(Set(sports.map(\.title)).count == sports.count)
        #expect(Set(sports.map(\.hue)).count == sports.count)
    }
}
