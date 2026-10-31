import GCPAPISync
import SwiftUI

/// The activities of a month, of one sport or all, as a table with each sport's totals.
struct MonthActivities: View {
    let first: GarminDate
    let sport: Sport?
    let workouts: [Workout]

    private var shown: [Workout] {
        let last = CalendarMonth.adding(months: 1, to: first).adding(days: -1)
        return workouts.filter { workout in
            workout.date >= first && workout.date <= last
                && (sport == nil || workout.sport == sport)
        }
    }

    private var title: String {
        let month = MonthlyStatisticsTable.title(first)
        return sport.map { String(localized: "\(month) · \($0.title)") } ?? month
    }

    var body: some View {
        let shown = shown
        ScrollView {
            ActivityLogTable(
                workouts: shown, days: Array(Set(shown.map(\.date))).sorted(by: >)
            )
            .padding(20)
        }
        .navigationTitle(title)
        .toolbarTitleDisplayMode(.inline)
    }
}
