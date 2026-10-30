import Foundation
import GCPAPISync

/// Months of the activity calendar, by their first day.
nonisolated enum CalendarMonth {
    /// The first day of the month containing `date`.
    static func first(of date: GarminDate) -> GarminDate {
        date.adding(days: 1 - date.day)
    }

    /// The first day of the month `months` after the one starting on `first`.
    static func adding(months: Int, to first: GarminDate) -> GarminDate {
        let index = first.year * 12 + (first.month - 1) + months
        return (try? GarminDate(year: index / 12, month: index % 12 + 1, day: 1)) ?? first
    }

    /// Every day of the month starting on `first`.
    static func days(of first: GarminDate) -> [GarminDate] {
        let next = adding(months: 1, to: first)
        return (0..<first.days(to: next)).map { first.adding(days: $0) }
    }

    /// The empty cells before the first day, for weeks starting on `calendar`'s first
    /// weekday.
    static func leadingBlanks(of first: GarminDate, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: first.startOfDay(in: calendar.timeZone))
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    /// The very short weekday names, starting with `calendar`'s first weekday.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }
}
