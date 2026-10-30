import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// `Format`'s numbers, counts, durations and Garmin's words.
@Suite struct BlackBoxFormatTests {
    // MARK: - Missing values

    @Test func missingValuesAreAnEnDash() {
        #expect(Format.duration(seconds: nil) == BlackBox.dash)
        #expect(Format.number(nil) == BlackBox.dash)
        #expect(Format.decimal(nil) == BlackBox.dash)
    }

    // MARK: - Duration

    @Test func durationMatchesTheDocumentedExample() {
        #expect(Format.duration(seconds: 27_120) == "7h 32m")
    }

    @Test(arguments: [
        (3660, "1h 1m"), (36_300, "10h 5m"), (32_340, "8h 59m"),
        (83_700, "23h 15m"),
    ])
    func durationShowsHoursAndMinutes(seconds: Int, expected: String) {
        #expect(Format.duration(seconds: seconds) == expected)
    }

    @Test func durationOfManyHoursKeepsCountingHours() {
        let text = Format.duration(seconds: 100 * 3600 + 5 * 60)
        #expect(text.hasPrefix("100h"))
        #expect(text.contains("5m"))
    }

    @Test(arguments: [0, 59, 60, 3599, 3600, 86_399, 86_400])
    func durationIsNeverEmptyOrADash(seconds: Int) {
        let text = Format.duration(seconds: seconds)
        #expect(!text.isEmpty)
        #expect(text != BlackBox.dash)
    }

    // MARK: - Numbers

    @Test(arguments: [0, 1, -1, 7, 999, 1000, 12_345, -12_345, 1_000_000, Int.max, Int.min])
    func numberIsLocalized(value: Int) {
        #expect(Format.number(value) == value.formatted())
    }

    @Test(arguments: [
        (52.34, "523"), (52.0, "520"), (0.0, "00"), (2.26, "23"), (2.24, "22"), (9.96, "100"),
    ])
    func decimalHasExactlyOneDecimal(value: Double, digits: String) {
        let text = Format.decimal(value)
        #expect(BlackBox.digits(text) == digits)
        let separator = text.dropLast().last
        #expect(separator == "." || separator == ",")
        #expect(text.last?.isNumber == true)
    }

    @Test func negativeDecimalKeepsItsSign() {
        let text = Format.decimal(-1.26)
        #expect(BlackBox.digits(text) == "13")
        #expect(text.hasPrefix("-") || text.hasPrefix("\u{2212}"))
    }

    // MARK: - Counts

    @Test(arguments: [(1, "1 day"), (2, "2 days"), (0, "0 days"), (7, "7 days"), (21, "21 days")])
    func daysAgreeWithTheirCount(count: Int, expected: String) {
        #expect(Format.days(count) == expected)
    }

    @Test func manyDaysArePlural() {
        let text = Format.days(1000)
        #expect(text.hasSuffix(" days"))
        #expect(BlackBox.digits(text) == "1000")
    }

    @Test(arguments: [
        (1, "1 activity"), (4, "4 activities"), (0, "0 activities"), (2, "2 activities"),
        (11, "11 activities"),
    ])
    func activitiesAgreeWithTheirCount(count: Int, expected: String) {
        #expect(Format.activities(count) == expected)
    }

    // MARK: - Clock and hours

    @Test(arguments: [
        (3130.0, "52:10"), (3930.0, "1:05:30"), (3600.0, "1:00:00"), (3599.0, "59:59"),
        (36_000.0, "10:00:00"), (90_061.0, "25:01:01"), (59.4, "0:59"), (60.0, "1:00"),
        (0.0, "0:00"), (7199.0, "1:59:59"),
    ])
    func clockShowsMinutesAndSecondsOrHours(seconds: Double, expected: String) {
        #expect(Format.clock(seconds: seconds) == expected)
    }

    @Test func clockBelowTenMinutesHasTwoDigitSeconds() {
        let text = Format.clock(seconds: 310)
        #expect(text.hasSuffix(":10"))
        #expect(text.split(separator: ":").count == 2)
        #expect(Int(text.split(separator: ":")[0]) == 5)
    }

    @Test func hoursMatchTheDocumentedExample() {
        #expect(Format.hours(seconds: 15_120) == "4h 12m")
    }

    @Test func hoursOfLargeTotalsKeepCountingHours() {
        #expect(Format.hours(seconds: 100 * 3600).hasPrefix("100h"))
        #expect(Format.hours(seconds: 45 * 60).contains("45m"))
    }

    // MARK: - Distances, elevation and pace

    @Test(arguments: [10_200.0, 42_195.0, 5000.0, 160_934.4])
    func distanceIsInTheUsersUnit(metres: Double) {
        let text = Format.distance(metres: metres)
        #expect(text.hasSuffix(Format.usesMiles ? " mi" : " km"), "\(text)")
        #expect(!text.contains("/"))
    }

    @Test func elevationMatchesTheDocumentedExamples() {
        // 640 m are 2,099.7 ft: the documentation's two examples are the same climb.
        let expected = Format.usesMiles ? "\(2100.formatted()) ft" : "640 m"
        #expect(Format.elevation(metres: 640) == expected)
    }

    @Test func elevationBelowSeaLevelKeepsItsSign() {
        let text = Format.elevation(metres: -430)
        #expect(text.hasPrefix("-") || text.hasPrefix("\u{2212}"))
        #expect(BlackBox.digits(text) == (Format.usesMiles ? "1411" : "430"))
    }

    @Test func runningPaceMatchesTheDocumentedExample() {
        let speed = 1000.0 / 307.0
        let expected = Format.usesMiles ? "8:14 /mi" : "5:07 /km"
        #expect(Format.pace(metresPerSecond: speed, sport: .running) == expected)
    }

    @Test func walkingIsAPaceToo() {
        let speed = 1000.0 / 600.0
        let expected = Format.usesMiles ? "16:06 /mi" : "10:00 /km"
        #expect(Format.pace(metresPerSecond: speed, sport: .walking) == expected)
    }

    @Test func swimmingPaceIsPerHundred() {
        let text = Format.pace(metresPerSecond: 100.0 / 95.0, sport: .swimming)
        #expect(text.contains("100"))
        #expect(text.hasPrefix("1:35") || text.hasPrefix("1:27"))
    }

    @Test(arguments: [Sport.cycling, .strength, .other])
    func otherSportsShowSpeed(sport: Sport) {
        let text = Format.pace(metresPerSecond: 26.6 / 3.6, sport: sport)
        if Format.usesMiles {
            #expect(BlackBox.digits(text) == "165")
        } else {
            #expect(text.hasSuffix(" km/h"))
            #expect(BlackBox.digits(text) == "266")
        }
        #expect(!text.contains("/km "))
    }

    // MARK: - Garmin's words

    @Test(arguments: [
        (0.0, "no benefit"), (0.5, "no benefit"), (1.0, "minor"), (1.5, "minor"),
        (2.0, "maintaining"), (2.5, "maintaining"), (3.0, "improving"), (3.5, "improving"),
        (4.0, "highly improving"), (4.5, "highly improving"), (5.0, "overreaching"),
    ])
    func trainingEffectUsesGarminsWords(value: Double, words: String) {
        #expect(Format.trainingEffect(value).lowercased().contains(words))
    }

    @Test(arguments: [3.0, 3.5, 3.9])
    func improvingIsNotHighlyImproving(value: Double) {
        #expect(!Format.trainingEffect(value).lowercased().contains("highly"))
    }

    @Test func benefitWithoutALabelIsNil() {
        #expect(Format.benefit(nil) == nil)
    }

    @Test(arguments: [
        "LACTATE_THRESHOLD", "AEROBIC_BASE", "TEMPO", "ANAEROBIC_CAPACITY", "VO2MAX", "RECOVERY",
        "SPRINT",
    ])
    func benefitIsInWords(label: String) throws {
        let text = try #require(Format.benefit(label))
        #expect(!text.contains("_"))
        #expect(text.first?.isUppercase == true)
        // Garmin's words name the benefit with at least one of the label's words.
        let words = label.lowercased().split(separator: "_").map { $0.replacing("max", with: "") }
        #expect(words.contains { text.lowercased().contains($0) }, "\(text)")
    }

    @Test func trainingMessageMatchesTheDocumentedExample() {
        #expect(Format.trainingMessage("IMPROVING_VO2_MAX_15") == "Improving VO2 max")
        #expect(Format.trainingMessage(nil) == nil)
    }

    @Test(arguments: [
        ("IMPROVING_AEROBIC_BASE_8", "Improving aerobic base"),
        ("HIGHLY_IMPROVING_VO2_MAX_26", "Highly improving VO2 max"),
        ("MAINTAINING_AEROBIC_FITNESS_3", "Maintaining aerobic fitness"),
    ])
    func trainingMessageIsASentence(message: String, sentence: String) {
        #expect(Format.trainingMessage(message) == sentence)
    }

    // MARK: - HRV status and stress

    @Test(arguments: [
        ("BALANCED", ColorRole.Status.good, "balanced"),
        ("UNBALANCED", ColorRole.Status.fair, "unbalanced"),
        ("POOR", ColorRole.Status.poor, "poor"),
    ])
    func hrvStatusHasALabelAndAStatusColor(
        status: String, role: ColorRole.Status, words: String
    ) throws {
        let presented = try #require(Format.hrvStatus(status))
        #expect(presented.label.lowercased().contains(words))
        #expect(presented.color.hex == ColorRole.status(role).color.hex)
    }

    @Test func lowHRVIsNotGood() throws {
        let presented = try #require(Format.hrvStatus("LOW"))
        #expect(presented.label.lowercased().contains("low"))
        #expect(presented.color.hex != ColorRole.status(.good).color.hex)
    }

    @Test func hrvWithoutStatusHasNoBadge() {
        #expect(Format.hrvStatus(nil) == nil)
    }

    @Test(arguments: [
        (0, ColorRole.StressLevel.rest), (10, .rest), (25, .rest), (26, .low), (40, .low),
        (50, .low), (51, .medium), (60, .medium), (75, .medium), (76, .high), (90, .high),
        (100, .high),
    ])
    func stressFollowsGarminsBands(level: Int, band: ColorRole.StressLevel) {
        #expect(ColorRole.StressLevel(level: level) == band)
        #expect(Format.stressColor(level).hex == ColorRole.stress(band).color.hex)
        #expect(Format.stressLabel(level).lowercased().contains(band.rawValue.lowercased()))
    }

    @Test func stressLabelsDifferBetweenBandsOnly() {
        let labels = (0...100).map(Format.stressLabel)
        #expect(Set(labels).count == 4)
        #expect(Set(labels[0...25]).count == 1)
        #expect(Set(labels[26...50]).count == 1)
        #expect(Set(labels[51...75]).count == 1)
        #expect(Set(labels[76...100]).count == 1)
    }
}

/// Miles or kilometres, and which day weeks start on.
@Suite struct BlackBoxUnitsAndCalendarTests {
    nonisolated private static let locales = ["en_US", "de_DE", "fr_FR", "ja_JP", "en_DE", "es_US"]

    @Test(arguments: locales)
    func metricNeverMeansMiles(identifier: String) {
        let locale = Locale(identifier: identifier)
        #expect(!Format.usesMiles(units: Settings.Units.metric.rawValue, locale: locale))
    }

    @Test(arguments: locales)
    func imperialAlwaysMeansMiles(identifier: String) {
        let locale = Locale(identifier: identifier)
        #expect(Format.usesMiles(units: Settings.Units.imperial.rawValue, locale: locale))
    }

    @Test(arguments: [
        ("en_US", true), ("es_US", true), ("de_DE", false), ("fr_FR", false), ("ja_JP", false),
        ("en_DE", false),
    ])
    func automaticFollowsTheRegion(identifier: String, miles: Bool) {
        let locale = Locale(identifier: identifier)
        #expect(Format.usesMiles(units: Settings.Units.automatic.rawValue, locale: locale) == miles)
        #expect(Format.usesMiles(units: nil, locale: locale) == miles)
    }

    @Test(arguments: ["furlongs", "", "METRIC", "Imperial"])
    func unknownUnitsFollowTheRegion(units: String) {
        for identifier in ["en_US", "de_DE"] {
            let locale = Locale(identifier: identifier)
            #expect(
                Format.usesMiles(units: units, locale: locale)
                    == Format.usesMiles(units: nil, locale: locale)
            )
        }
    }

    @Test func currentRegionDecidesWithoutAChoice() {
        let region = Locale.current.measurementSystem == .us
        #expect(Format.usesMiles(units: nil) == region)
        #expect(Format.usesMiles(units: Settings.Units.automatic.rawValue) == region)
    }

    @Test func usesMilesReadsTheSavedChoice() {
        let saved = UserDefaults.standard.string(forKey: Preferences.unitsKey)
        #expect(Format.usesMiles == Format.usesMiles(units: saved))
    }

    @Test func weeksStartOnTheChosenDay() {
        #expect(Calendar.app(weekStart: Settings.WeekStart.monday.rawValue).firstWeekday == 2)
        #expect(Calendar.app(weekStart: Settings.WeekStart.sunday.rawValue).firstWeekday == 1)
    }

    @Test(arguments: [Settings.WeekStart.automatic.rawValue, "tuesday", ""])
    func automaticOrUnknownWeekStartFollowsTheRegion(weekStart: String) {
        let current = Calendar.current
        #expect(Calendar.app(weekStart: weekStart).firstWeekday == current.firstWeekday)
        #expect(Calendar.app(weekStart: nil).firstWeekday == current.firstWeekday)
    }

    @Test(arguments: Settings.WeekStart.allCases)
    func appCalendarIsOtherwiseTheCurrentOne(weekStart: Settings.WeekStart) {
        let calendar = Calendar.app(weekStart: weekStart.rawValue)
        #expect(calendar.identifier == Calendar.current.identifier)
        #expect(calendar.timeZone == Calendar.current.timeZone)
    }

    @Test func appCalendarReadsTheSavedChoice() {
        let saved = UserDefaults.standard.string(forKey: Preferences.weekStartKey)
        #expect(Calendar.app.firstWeekday == Calendar.app(weekStart: saved).firstWeekday)
    }

    @Test func trainingWeeksStartOnTheChosenDay() {
        // 2026-10-30 is a Friday.
        let friday = GarminDate.day("2026-10-30")
        let monday = Calendar.app(weekStart: Settings.WeekStart.monday.rawValue)
        let sunday = Calendar.app(weekStart: Settings.WeekStart.sunday.rawValue)
        #expect(TrainingWeek.weekStart(of: friday, calendar: monday) == .day("2026-10-26"))
        #expect(TrainingWeek.weekStart(of: friday, calendar: sunday) == .day("2026-10-25"))
    }

    @Test func preferenceKeysAreDistinct() {
        #expect(!Preferences.unitsKey.isEmpty)
        #expect(!Preferences.weekStartKey.isEmpty)
        #expect(Preferences.unitsKey != Preferences.weekStartKey)
    }
}
