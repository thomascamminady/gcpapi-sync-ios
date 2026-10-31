import Foundation

/// Text for workouts, in the units of the user's region.
extension Format {
    /// Whether distances are in miles rather than kilometres: the user's choice, or the
    /// region's.
    nonisolated static var usesMiles: Bool {
        usesMiles(units: UserDefaults.standard.string(forKey: Preferences.unitsKey))
    }

    /// Whether `units`, a ``Settings/Units`` raw value, mean miles in `locale`.
    nonisolated static func usesMiles(units: String?, locale: Locale = .current) -> Bool {
        switch units {
        case Settings.Units.metric.rawValue: false
        case Settings.Units.imperial.rawValue: true
        default: locale.measurementSystem != .metric
        }
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

    /// In kilometres or miles, with two decimals below 10 (`5.03 km`, `6.21 mi`) and one from
    /// 10 on (`10.2 km`, `26.2 mi`).
    nonisolated static func distance(metres: Double) -> String {
        let measurement = Measurement(value: metres, unit: UnitLength.meters)
            .converted(to: usesMiles ? .miles : .kilometers)
        return measurement.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(
                    .fractionLength(abs(measurement.value) < 10 ? 2 : 1))))
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
    /// `Improving VO2 max`. Known messages are translated; others are Garmin's words.
    nonisolated static func trainingMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let words = message.split(separator: "_").filter { Int($0) == nil }.map(String.init)
        guard !words.isEmpty else { return nil }
        return knownMessage(words) ?? sentence(words)
    }

    /// A message Garmin uses: a whole phrase, or a verb and what it acts on.
    nonisolated private static func knownMessage(_ words: [String]) -> String? {
        switch words.joined(separator: "_") {
        case "NO_AEROBIC_BENEFIT": return String(localized: "No aerobic benefit")
        case "MINOR_AEROBIC_BENEFIT": return String(localized: "Minor aerobic benefit")
        case "NO_ANAEROBIC_BENEFIT": return String(localized: "No anaerobic benefit")
        case "MINOR_ANAEROBIC_BENEFIT": return String(localized: "Minor anaerobic benefit")
        case "RECOVERY": return String(localized: "Recovery")
        case "OVERREACHING": return String(localized: "Overreaching")
        default: break
        }
        let verbs: [(words: [String], phrase: (String) -> String)] = [
            (["HIGHLY", "IMPROVING"], { String(localized: "Highly improving \($0)") }),
            (["IMPROVING"], { String(localized: "Improving \($0)") }),
            (["MAINTAINING"], { String(localized: "Maintaining \($0)") }),
            (["IMPACTING"], { String(localized: "Impacting \($0)") }),
            (["OVERREACHING"], { String(localized: "Overreaching \($0)") }),
        ]
        for verb in verbs where words.starts(with: verb.words) {
            return trainingAspect(words.dropFirst(verb.words.count).joined(separator: "_"))
                .map(verb.phrase)
        }
        return nil
    }

    /// What a training effect message says is improved or maintained.
    nonisolated private static func trainingAspect(_ name: String) -> String? {
        switch name {
        case "AEROBIC_BASE": String(localized: "aerobic base")
        case "AEROBIC_FITNESS": String(localized: "aerobic fitness")
        case "AEROBIC_ENDURANCE": String(localized: "aerobic endurance")
        case "LACTATE_THRESHOLD": String(localized: "lactate threshold")
        case "VO2_MAX": String(localized: "VO2 max")
        case "TEMPO": String(localized: "tempo")
        case "SPEED": String(localized: "speed")
        case "ANAEROBIC_BASE": String(localized: "anaerobic base")
        case "ANAEROBIC_FITNESS": String(localized: "anaerobic fitness")
        case "ANAEROBIC_CAPACITY": String(localized: "anaerobic capacity")
        case "ANAEROBIC_POWER": String(localized: "anaerobic power")
        case "ANAEROBIC_CAPACITY_AND_POWER": String(localized: "anaerobic capacity and power")
        default: nil
        }
    }

    /// Garmin's words as a sentence: `IMPROVING_SOMETHING` as `Improving something`.
    nonisolated private static func sentence(_ words: [String]) -> String {
        let lowered = words.map { $0 == "VO2" ? $0 : $0.lowercased() }
        let first = lowered[0]
        return ([first.prefix(1).uppercased() + first.dropFirst()] + lowered.dropFirst())
            .joined(separator: " ")
    }
}
