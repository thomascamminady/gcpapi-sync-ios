import EventKit
import Foundation

/// Keeps a calendar named "Activities" in the Calendar app with an event per activity.
///
/// Calendar access is asked for only when the user turns this on. The calendar belongs to the
/// app: syncing replaces its events in the synced range and touches no other calendar.
final class CalendarSync {
    static let calendarTitle = String(localized: "Activities")
    private static let identifierKey = "activityCalendarIdentifier"

    private let store = EKEventStore()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Ask for access to the calendars, if not granted yet.
    func requestAccess() async throws -> Bool {
        if isAuthorized {
            return true
        }
        return try await store.requestFullAccessToEvents()
    }

    /// Replace the calendar's events from `first` on with one per activity in `workouts`.
    /// Returns the number of events written.
    @discardableResult
    func sync(_ workouts: [Workout], from first: Date) throws -> Int {
        guard isAuthorized else { return 0 }
        let calendar = try activityCalendar()
        let range = store.predicateForEvents(
            withStart: first, end: .now.addingTimeInterval(86_400), calendars: [calendar])
        for event in store.events(matching: range) {
            try store.remove(event, span: .thisEvent, commit: false)
        }
        var written = 0
        for workout in workouts {
            guard let start = workout.start, start >= first else { continue }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = CalendarText.title(of: workout)
            event.notes = CalendarText.notes(of: workout)
            event.url = CalendarText.link(of: workout)
            event.startDate = start
            event.endDate = start.addingTimeInterval(max(60, workout.duration))
            try store.save(event, span: .thisEvent, commit: false)
            written += 1
        }
        try store.commit()
        return written
    }

    /// Delete the app's calendar, as when turning the sync off.
    func removeCalendar() throws {
        guard isAuthorized, let identifier = defaults.string(forKey: Self.identifierKey),
            let calendar = store.calendar(withIdentifier: identifier)
        else { return }
        try store.removeCalendar(calendar, commit: true)
        defaults.removeObject(forKey: Self.identifierKey)
    }

    /// The app's calendar, created the first time: in iCloud when the user's calendars are
    /// there, otherwise on the device.
    private func activityCalendar() throws -> EKCalendar {
        if let identifier = defaults.string(forKey: Self.identifierKey),
            let calendar = store.calendar(withIdentifier: identifier)
        {
            return calendar
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = Self.calendarTitle
        calendar.source =
            store.defaultCalendarForNewEvents?.source
            ?? store.sources.first { $0.sourceType == .local }
        try store.saveCalendar(calendar, commit: true)
        defaults.set(calendar.calendarIdentifier, forKey: Self.identifierKey)
        return calendar
    }
}
