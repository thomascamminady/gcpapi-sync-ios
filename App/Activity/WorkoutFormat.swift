import Foundation

/// Text for workouts, in the units of the user's region.
extension Format {
    /// Whether distances are in miles rather than kilometres.
    nonisolated static var usesMiles: Bool {
        Locale.current.measurementSystem != .metric
    }

    /// `52:10`, or `1:05:30` from an hour on.
    nonisolated static func clock(seconds: Double) -> String {
        Duration.seconds(seconds.rounded()).formatted(
            .time(pattern: seconds < 3600 ? .minuteSecond : .hourMinuteSecond))
    }

    /// `4h 12m`, for totals.
    nonisolated static func hours(seconds: Double) -> String {
        duration(seconds: Int(seconds.rounded()))
    }

    /// `10.2 km` or `6.3 mi`.
    nonisolated static func distance(metres: Double) -> String {
        let measurement = Measurement(value: metres, unit: UnitLength.meters)
            .converted(to: usesMiles ? .miles : .kilometers)
        return measurement.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(
                    .fractionLength(measurement.value < 100 ? 2 : 1))))
    }

    /// `640 m` or `2,100 ft`.
    nonisolated static func elevation(metres: Double) -> String {
        Measurement(value: metres, unit: UnitLength.meters)
            .converted(to: usesMiles ? .feet : .meters)
            .formatted(
                .measurement(
                    width: .abbreviated, usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// Pace for running and walking (`5:07 /km`), per 100 m for swimming, and speed
    /// (`26.6 km/h`) for everything else.
    nonisolated static func pace(metresPerSecond speed: Double, sport: Sport) -> String {
        switch sport {
        case .running, .walking:
            let unit = usesMiles ? 1609.344 : 1000
            return "\(clock(seconds: unit / speed)) \(usesMiles ? "/mi" : "/km")"
        case .swimming:
            return "\(clock(seconds: 100 / speed)) /100 m"
        case .cycling, .strength, .other:
            return Measurement(value: speed, unit: UnitSpeed.metersPerSecond)
                .converted(to: usesMiles ? .milesPerHour : .kilometersPerHour)
                .formatted(
                    .measurement(
                        width: .abbreviated, usage: .asProvided,
                        numberFormatStyle: .number.precision(.fractionLength(1))))
        }
    }

    /// Garmin's words for a training effect from 0 to 5.
    nonisolated static func trainingEffect(_ value: Double) -> String {
        switch value {
        case ..<1: String(localized: "No benefit")
        case 1..<2: String(localized: "Minor benefit")
        case 2..<3: String(localized: "Maintaining")
        case 3..<4: String(localized: "Improving")
        case 4..<5: String(localized: "Highly improving")
        default: String(localized: "Overreaching")
        }
    }

    /// Garmin's primary benefit, such as `LACTATE_THRESHOLD`, in words.
    nonisolated static func benefit(_ label: String?) -> String? {
        switch label {
        case "RECOVERY": String(localized: "Recovery")
        case "AEROBIC_BASE": String(localized: "Base")
        case "TEMPO": String(localized: "Tempo")
        case "LACTATE_THRESHOLD": String(localized: "Threshold")
        case "VO2MAX": String(localized: "VO2 Max")
        case "ANAEROBIC_CAPACITY": String(localized: "Anaerobic")
        case "SPRINT": String(localized: "Sprint")
        default: nil
        }
    }

    /// Garmin's training effect message, such as `IMPROVING_VO2_MAX_15`, as a sentence:
    /// `Improving VO2 max`.
    nonisolated static func trainingMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let words = message.split(separator: "_").filter { Int($0) == nil }.map { word in
            word == "VO2" ? "VO2" : word.lowercased()
        }
        guard let first = words.first else { return nil }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst())
            .joined(separator: " ")
    }
}
