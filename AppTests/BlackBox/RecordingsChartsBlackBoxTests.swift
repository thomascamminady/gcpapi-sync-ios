import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

@Suite("TrackMeasure")
struct BlackBoxTrackMeasureTests {
    static let mile = 1609.344

    static func sample(
        speed: Double? = nil, heartRate: Double? = nil, altitude: Double? = nil,
        cadence: Double? = nil, power: Double? = nil
    ) -> ActivityTrack.Sample {
        ActivityTrack.Sample(
            elapsed: 10, distance: 40, heartRate: heartRate, speed: speed, altitude: altitude,
            cadence: cadence, power: power)
    }

    static func hasLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    @Test("Pace for running, walking and swimming; speed otherwise", arguments: Sport.allCases)
    func usesPace(sport: Sport) {
        #expect(TrackMeasure.usesPace(sport) == [.running, .walking, .swimming].contains(sport))
    }

    @Test("Heart rate, cadence and power are plotted as recorded", arguments: Sport.allCases)
    func plainValues(sport: Sport) {
        let sample = Self.sample(heartRate: 151, cadence: 172, power: 245)
        #expect(TrackMeasure.heartRate.value(sample, sport: sport) == 151)
        #expect(TrackMeasure.cadence.value(sample, sport: sport) == 172)
        #expect(TrackMeasure.power.value(sample, sport: sport) == 245)
        let empty = Self.sample()
        for measure in TrackMeasure.allCases {
            #expect(measure.value(empty, sport: sport) == nil, "\(measure)")
        }
    }

    @Test("Pace is negated minutes per kilometre or mile", arguments: [Sport.running, .walking])
    func pace(sport: Sport) throws {
        let unit = Format.usesMiles ? Self.mile : 1000
        let value = try #require(TrackMeasure.pace.value(Self.sample(speed: 4), sport: sport))
        #expect(abs(value - -(unit / 4) / 60) < 1e-9)
        let faster = try #require(TrackMeasure.pace.value(Self.sample(speed: 5), sport: sport))
        #expect(faster > value)
    }

    @Test("Swimming pace is negated minutes per 100 m")
    func swimmingPace() throws {
        let value = try #require(
            TrackMeasure.pace.value(Self.sample(speed: 1.25), sport: .swimming))
        #expect(value < 0)
        if !Format.usesMiles {
            #expect(abs(value - -(100 / 1.25) / 60) < 1e-9)
        }
        let faster = try #require(
            TrackMeasure.pace.value(Self.sample(speed: 1.5), sport: .swimming))
        #expect(faster > value)
    }

    @Test(
        "Speed is in kilometres or miles an hour", arguments: [Sport.cycling, .strength, .other])
    func speed(sport: Sport) throws {
        let value = try #require(TrackMeasure.pace.value(Self.sample(speed: 10), sport: sport))
        let expected = Format.usesMiles ? 10 * 3600 / Self.mile : 36
        #expect(abs(value - expected) < 1e-5 * expected, "\(value)")
    }

    @Test("Pace without speed is not plotted; standing still is not infinite")
    func paceWithoutSpeed() {
        #expect(TrackMeasure.pace.value(Self.sample(), sport: .running) == nil)
        let still = TrackMeasure.pace.value(Self.sample(speed: 0), sport: .running)
        #expect(still.map(\.isFinite) ?? true)
    }

    @Test("Elevation is in metres or feet", arguments: [Sport.running, .cycling])
    func elevation(sport: Sport) throws {
        let value = try #require(
            TrackMeasure.elevation.value(Self.sample(altitude: 100), sport: sport))
        let expected = Format.usesMiles ? 100 / 0.3048 : 100
        #expect(abs(value - expected) < 1e-5 * expected, "\(value)")
    }

    @Test("Pace text has minutes, seconds and the unit")
    func paceText() {
        let text = TrackMeasure.pace.format(-4.5, sport: .running)
        #expect(text.contains("4:30"), "\(text)")
        #expect(text.contains(Format.usesMiles ? "mi" : "km"), "\(text)")
        let label = TrackMeasure.pace.axisLabel(-4.5, sport: .running)
        #expect(label.contains("4:30"), "\(label)")
        #expect(!label.contains("-"))
        #expect(!Self.hasLetters(label), "\(label)")
    }

    @Test("Speed text has the unit")
    func speedText() {
        let text = TrackMeasure.pace.format(36, sport: .cycling)
        #expect(text.contains("36"), "\(text)")
        if Format.usesMiles {
            #expect(!text.contains("km"), "\(text)")
        } else {
            #expect(text.contains("km/h"), "\(text)")
        }
        let label = TrackMeasure.pace.axisLabel(36, sport: .cycling)
        #expect(label.contains("36"))
        #expect(!Self.hasLetters(label), "\(label)")
    }

    @Test("Heart rate, elevation and power texts")
    func otherTexts() {
        let heart = TrackMeasure.heartRate.format(150, sport: .running)
        #expect(heart.contains("150") && heart.contains("bpm"), "\(heart)")
        let elevation = TrackMeasure.elevation.format(640, sport: .running)
        #expect(elevation.contains("640"), "\(elevation)")
        #expect(elevation.contains(Format.usesMiles ? "ft" : "m"), "\(elevation)")
        let power = TrackMeasure.power.format(250, sport: .cycling)
        #expect(power.contains("250") && power.contains("W"), "\(power)")
    }

    @Test("Axis labels leave out the unit that the text has", arguments: TrackMeasure.allCases)
    func axisLabels(measure: TrackMeasure) {
        let values: [TrackMeasure: Double] = [
            .heartRate: 150, .pace: -5, .elevation: 640, .cadence: 170, .power: 250,
        ]
        let value = values[measure] ?? 100
        let text = measure.format(value, sport: .running)
        let label = measure.axisLabel(value, sport: .running)
        #expect(Self.hasLetters(text), "\(text)")
        #expect(!Self.hasLetters(label), "\(label)")
        #expect(text != label)
        #expect(!label.isEmpty)
    }

    @Test("Titles: pace when running, speed when riding")
    func titles() {
        for measure in TrackMeasure.allCases {
            for sport in Sport.allCases {
                #expect(!measure.title(for: sport).isEmpty)
            }
            #expect(measure.id == measure)
        }
        #expect(TrackMeasure.pace.title(for: .running) != TrackMeasure.pace.title(for: .cycling))
    }

    @Test("Heart rate is red and elevation brown")
    func hues() {
        #expect(TrackMeasure.heartRate.hue == .red)
        #expect(TrackMeasure.elevation.hue == .brown)
    }
}

@Suite("TrackChart.domain")
struct BlackBoxTrackChartDomainTests {
    @Test("Contains the middle 96%, with modest padding", arguments: 0..<6)
    func middle(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 11_000)
        let values = (0...1000).map(Double.init).shuffled(using: &random)
        let domain = TrackChart.domain(values)
        #expect(domain.lowerBound <= 20 && domain.upperBound >= 980, "\(domain)")
        #expect(domain.lowerBound >= -250 && domain.upperBound <= 1250, "\(domain)")
    }

    @Test("A few outliers do not stretch the range")
    func outliers() {
        var values = (0..<1000).map { 100 + Double($0) / 10 }
        values += [Double](repeating: 10_000, count: 5) + [Double](repeating: -10_000, count: 5)
        let domain = TrackChart.domain(values)
        #expect(domain.lowerBound <= 102 && domain.upperBound >= 198, "\(domain)")
        #expect(domain.lowerBound >= 75 && domain.upperBound <= 225, "\(domain)")
    }

    @Test("The order of the values does not matter", arguments: 0..<6)
    func order(seed: Int) {
        var random = RecordingRandom(seed: UInt64(seed) + 12_000)
        let values = (0..<500).map { _ in random.double(-50...300) }
        #expect(TrackChart.domain(values) == TrackChart.domain(values.shuffled(using: &random)))
        #expect(TrackChart.domain(values) == TrackChart.domain(values.sorted()))
    }

    @Test("Negative values, as pace is plotted")
    func negative() {
        let values = (0...200).map { -6 + Double($0) / 100 }
        let domain = TrackChart.domain(values)
        #expect(domain.lowerBound <= -5.96 && domain.upperBound >= -4.04, "\(domain)")
        #expect(domain.lowerBound >= -6.5 && domain.upperBound <= -3.5, "\(domain)")
    }

    @Test("Constant values still make a range", arguments: [[5.0], [5, 5, 5], [0, 0], [-3, -3]])
    func constant(values: [Double]) throws {
        let value = try #require(values.first)
        let domain = TrackChart.domain(values)
        #expect(domain.contains(value))
        #expect(domain.lowerBound < domain.upperBound, "\(domain)")
    }

    @Test("No values do not crash")
    func empty() {
        let domain = TrackChart.domain([])
        #expect(domain.lowerBound <= domain.upperBound)
    }
}

@Suite("ZoneStyle")
struct BlackBoxZoneStyleTests {
    /// Colors compared as drawn in light and dark mode; dynamic colors are not `==`.
    static func resolved(_ color: Color) -> [Color.Resolved] {
        [ColorScheme.light, .dark].map { scheme in
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            return color.resolve(in: environment)
        }
    }

    @Test("Colors for zones 1 to 7, the user's zone colors")
    func colors() {
        #expect(ZoneStyle.colors.count == 7)
        for (index, color) in ZoneStyle.colors.enumerated() {
            #expect(
                Self.resolved(color) == Self.resolved(ColorRole.zone(index).color), "zone \(index)")
        }
    }

    @Test("Zones have different colors")
    func distinct() {
        let colors = ZoneStyle.colors.map(Self.resolved)
        #expect(Set(colors).count == colors.count)
    }

    @Test("Without a zone the fallback", arguments: [Color.pink, .mint, .clear])
    func fallback(color: Color) {
        #expect(Self.resolved(ZoneStyle.color(zone: nil, fallback: color)) == Self.resolved(color))
    }

    @Test("A zone has its color", arguments: 0..<5)
    func zone(index: Int) throws {
        let color = try #require(ZoneStyle.colors.dropFirst(index).first)
        #expect(
            Self.resolved(ZoneStyle.color(zone: index, fallback: .clear)) == Self.resolved(color))
    }
}

@Suite("Strength sets")
struct BlackBoxStrengthTests {
    @Test(
        "Exercise categories from the FIT profile",
        arguments: [
            (0, ["bench", "press"]), (1, ["calf", "raise"]), (2, ["cardio"]), (3, ["carry"]),
            (4, ["chop"]), (5, ["core"]), (6, ["crunch"]), (7, ["curl"]), (8, ["dead"]),
            (9, ["fly"]), (10, ["hip", "raise"]), (11, ["hip", "stability"]),
            (12, ["hip", "swing"]), (13, ["hyper"]), (14, ["lateral", "raise"]),
            (15, ["leg", "curl"]), (16, ["leg", "raise"]), (17, ["lunge"]), (18, ["olympic"]),
            (19, ["plank"]), (20, ["plyo"]), (21, ["pull"]), (22, ["push"]), (23, ["row"]),
            (24, ["shoulder", "press"]), (25, ["shoulder", "stability"]), (26, ["shrug"]),
            (27, ["sit"]), (28, ["squat"]), (29, ["total", "body"]), (30, ["tricep"]),
            (31, ["warm"]), (32, ["run"]),
        ] as [(Int, [String])])
    func category(number: Int, words: [String]) throws {
        let name = try #require(ExerciseCategory.name(number))
        let normalized = name.lowercased().replacingOccurrences(of: "_", with: " ")
        for word in words {
            #expect(normalized.contains(word), "\(name)")
        }
    }

    @Test("Category names are distinct")
    func distinct() {
        let names = (0...32).compactMap(ExerciseCategory.name)
        #expect(names.count == 33)
        #expect(Set(names).count == names.count)
    }

    @Test(
        "Categories outside the FIT profile have no name",
        arguments: [nil, 33, 40, 1000, 10_000] as [Int?])
    func outsideProfile(category: Int?) {
        #expect(ExerciseCategory.name(category) == nil)
    }

    @Test("Logged sets leave out rests and empty sets, in order")
    func loggedActive() {
        let squat = FITActivity.ExerciseSet(
            duration: 40, repetitions: 8, weight: 80, isActive: true, category: 28)
        let rest = FITActivity.ExerciseSet(duration: 90, isActive: false)
        let restWithReps = FITActivity.ExerciseSet(repetitions: 3, weight: 50, isActive: false)
        let press = FITActivity.ExerciseSet(repetitions: 10, isActive: true, category: 0)
        let plank = FITActivity.ExerciseSet(isActive: true, category: 19)
        let curls = FITActivity.ExerciseSet(repetitions: 12, isActive: true)
        let nothing = FITActivity.ExerciseSet(isActive: true)
        let sets = [squat, rest, press, restWithReps, nothing, plank, rest, curls]
        #expect(SetsCard.logged(sets) == [squat, press, plank, curls])
        #expect(SetsCard.logged([]).isEmpty)
        #expect(SetsCard.logged([rest, restWithReps, nothing]).isEmpty)
    }

    @Test("A set's detail: repetitions, weight and time")
    func detail() {
        let set = FITActivity.ExerciseSet(duration: 45, repetitions: 8, weight: 80, isActive: true)
        let text = SetsCard.detail(set)
        #expect(text.hasPrefix("8 × "), "\(text)")
        #expect(text.hasSuffix(" · 0:45"), "\(text)")
        if !Format.usesMiles {
            #expect(text == "8 × 80 kg · 0:45")
        }
    }

    @Test("A set's detail leaves out what is missing")
    func partialDetail() {
        let repsOnly = SetsCard.detail(FITActivity.ExerciseSet(repetitions: 12, isActive: true))
        #expect(repsOnly.contains("12"), "\(repsOnly)")
        #expect(!repsOnly.contains("kg") && !repsOnly.contains(":"), "\(repsOnly)")
        let noTime = SetsCard.detail(
            FITActivity.ExerciseSet(repetitions: 8, weight: 80, isActive: true))
        #expect(noTime.hasPrefix("8 × "), "\(noTime)")
        #expect(!noTime.contains(":") && !noTime.contains("·"), "\(noTime)")
        let long = SetsCard.detail(
            FITActivity.ExerciseSet(duration: 125, repetitions: 5, weight: 100, isActive: true))
        #expect(long.hasSuffix("2:05"), "\(long)")
    }
}
