import Foundation
import GCPAPISync

/// Turns health days and activities into files: CSV for spreadsheets, JSON for programs,
/// iCalendar for calendars and GPX for maps. Values are in SI units with a dot as the
/// decimal separator, whatever the region, so the files read the same everywhere.
nonisolated enum Exporter {
    static let dailyHeader = [
        "date", "steps", "step_goal", "resting_heart_rate", "hrv_ms", "hrv_status",
        "sleep_seconds", "deep_sleep_seconds", "light_sleep_seconds", "rem_sleep_seconds",
        "awake_seconds", "sleep_score", "stress", "body_battery_low", "body_battery_high",
        "active_calories", "intensity_minutes", "vo2max_estimate",
    ]

    static let activityHeader = [
        "id", "name", "type", "sport", "date", "start", "duration_seconds", "distance_metres",
        "average_speed_mps", "average_heart_rate", "max_heart_rate", "elevation_gain_metres",
        "calories", "average_power", "normalized_power", "cadence", "training_load",
        "aerobic_effect", "anaerobic_effect", "primary_benefit",
    ]

    /// One row per day, oldest first.
    static func dailyCSV(_ days: [DayHealth]) -> String {
        csv(header: dailyHeader, rows: days.sorted { $0.date < $1.date }.map(dailyRow))
    }

    /// One row per activity, newest first.
    static func activitiesCSV(_ workouts: [Workout]) -> String {
        csv(header: activityHeader, rows: workouts.sorted(by: newestFirst).map(activityRow))
    }

    static func dailyRow(_ day: DayHealth) -> [String] {
        [
            "\(day.date)", text(day.steps), text(day.stepGoal), text(day.restingHeartRate),
            text(day.hrv), day.hrvStatus ?? "", text(day.sleep?.total), text(day.sleep?.deep),
            text(day.sleep?.light), text(day.sleep?.rem), text(day.sleep?.awake),
            text(day.sleep?.score), text(day.stress), text(day.bodyBatteryLow),
            text(day.bodyBatteryHigh), text(day.activeCalories), text(day.intensityMinutes),
            text(day.vo2max),
        ]
    }

    static func activityRow(_ workout: Workout) -> [String] {
        [
            "\(workout.id)", workout.name, workout.typeKey, workout.sport.rawValue,
            "\(workout.date)", workout.start.map { $0.formatted(.iso8601) } ?? "",
            text(workout.duration), text(workout.distance), text(workout.averageSpeed),
            text(workout.averageHeartRate), text(workout.maxHeartRate),
            text(workout.elevationGain), text(workout.calories), text(workout.averagePower),
            text(workout.normalizedPower), text(workout.cadence), text(workout.trainingLoad),
            text(workout.aerobicEffect), text(workout.anaerobicEffect),
            workout.primaryBenefit ?? "",
        ]
    }

    /// Everything as one JSON document.
    static func json(days: [DayHealth], workouts: [Workout]) throws -> Data {
        struct Export: Encodable {
            let days: [DayHealth]
            let activities: [Workout]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(
            Export(
                days: days.sorted { $0.date < $1.date },
                activities: workouts.sorted(by: newestFirst)))
    }

    /// An iCalendar file with an event per activity. Events keep their identifier, so
    /// importing the file again updates them.
    static func calendar(_ workouts: [Workout], now: Date = .now) -> String {
        var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//gcpapi-sync-ios//Activities//EN"]
        for workout in workouts.sorted(by: newestFirst) {
            guard let start = workout.start else { continue }
            lines += [
                "BEGIN:VEVENT",
                "UID:garmin-activity-\(workout.id)@gcpapi-sync",
                "DTSTAMP:\(icsDate(now))",
                "DTSTART:\(icsDate(start))",
                "DTEND:\(icsDate(start.addingTimeInterval(workout.duration)))",
                "SUMMARY:\(icsText(CalendarText.title(of: workout)))",
                "DESCRIPTION:\(icsText(CalendarText.notes(of: workout)))",
                "URL:\(CalendarText.link(of: workout).absoluteString)",
                "END:VEVENT",
            ]
        }
        lines.append("END:VCALENDAR")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// A GPX track of a recording's located records.
    static func gpx(_ recording: FITActivity, name: String) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="gcpapi-sync-ios" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "<trk><name>\(xml(name))</name><trkseg>",
        ]
        for record in recording.records {
            guard let latitude = record.latitude, let longitude = record.longitude else { continue }
            var point = #"<trkpt lat="\#(number(latitude))" lon="\#(number(longitude))">"#
            if let altitude = record.altitude {
                point += "<ele>\(number(altitude))</ele>"
            }
            point += "<time>\(record.time.formatted(.iso8601))</time></trkpt>"
            lines.append(point)
        }
        lines += ["</trkseg></trk>", "</gpx>"]
        return lines.joined(separator: "\n") + "\n"
    }

    /// `existing` CSV with `rows` added, replacing rows whose first field matches.
    static func merge(
        _ existing: String?, header: [String], rows: [[String]], newestFirst: Bool
    )
        -> String
    {
        var byKey: [String: [String]] = [:]
        for row in parse(existing ?? "").dropFirst() where row.first.map({ !$0.isEmpty }) == true {
            byKey[row[0]] = row
        }
        for row in rows {
            byKey[row[0]] = row
        }
        let ordered = byKey.keys.sorted().map { byKey[$0] ?? [] }
        return csv(header: header, rows: newestFirst ? ordered.reversed() : ordered)
    }

    /// The rows of a CSV document, honoring quoted fields.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var characters = text.makeIterator()
        while let character = characters.next() {
            if quoted {
                if character == "\"" {
                    if let next = characters.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            quoted = false
                            consume(next, &field, &row, &rows, &quoted)
                        }
                    } else {
                        quoted = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                consume(character, &field, &row, &rows, &quoted)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    private static func consume(
        _ character: Character, _ field: inout String, _ row: inout [String],
        _ rows: inout [[String]], _ quoted: inout Bool
    ) {
        switch character {
        case "\"" where field.isEmpty: quoted = true
        case ",":
            row.append(field)
            field = ""
        case "\n", "\r\n":
            row.append(field)
            rows.append(row)
            row = []
            field = ""
        case "\r": break
        default: field.append(character)
        }
    }

    static func csv(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n")
            + "\n"
    }

    /// A field quoted when it holds a comma, a quote or a line break.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { [",", "\"", "\n", "\r"].contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func newestFirst(_ lhs: Workout, _ rhs: Workout) -> Bool {
        (lhs.start ?? .distantPast, lhs.id) > (rhs.start ?? .distantPast, rhs.id)
    }

    private static func text(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func text(_ value: Double?) -> String {
        value.map(number) ?? ""
    }

    /// A number without grouping, a dot as decimal separator and at most six decimals.
    static func number(_ value: Double) -> String {
        value.formatted(
            .number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never)
                .precision(.fractionLength(0...6)))
    }

    /// `20261029T070000Z`: iCalendar's basic UTC format.
    private static func icsDate(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(
                dateSeparator: .omitted, dateTimeSeparator: .standard, timeSeparator: .omitted,
                timeZoneSeparator: .omitted, includingFractionalSeconds: false, timeZone: .gmt))
    }

    private static func icsText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Lines longer than 75 bytes continue on the next, as iCalendar requires.
    private static func fold(_ line: String) -> String {
        var folded = ""
        var length = 0
        for character in line {
            let size = String(character).utf8.count
            if length + size > 75 {
                folded += "\r\n "
                length = 1
            }
            folded.append(character)
            length += size
        }
        return folded
    }

    private static func xml(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(
            of: "<", with: "&lt;"
        )
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// How an activity reads in a calendar.
nonisolated enum CalendarText {
    /// `Morning Run · 10.2 km`, or the duration without a distance.
    static func title(of workout: Workout) -> String {
        let extent =
            workout.distance.map(Format.distance) ?? Format.clock(seconds: workout.duration)
        return "\(workout.name) · \(extent)"
    }

    /// The activity's numbers, one a line.
    static func notes(of workout: Workout) -> String {
        [
            String(localized: "Duration \(Format.clock(seconds: workout.duration))"),
            workout.averageSpeed.map {
                Format.pace(metresPerSecond: $0, sport: workout.sport)
            },
            workout.averageHeartRate.map {
                String(localized: "Average heart rate \(Int($0.rounded())) bpm")
            },
            workout.trainingLoad.map { String(localized: "Training load \(Int($0.rounded()))") },
            workout.aerobicEffect.map { effect in
                let value = effect.formatted(.number.precision(.fractionLength(1)))
                return String(localized: "Aerobic training effect \(value)")
            },
        ].compactMap(\.self).joined(separator: "\n")
    }

    /// The activity on Garmin Connect.
    static func link(of workout: Workout) -> URL {
        URL(string: "https://connect.garmin.com/modern/activity/\(workout.id)")
            ?? URL(filePath: "/")
    }
}
