import GCPAPISync
import SwiftUI

/// The days a screen shows: one of its usual spans up to today, or any days the user picks.
nonisolated enum RangeChoice: Hashable, Sendable {
    /// The last `days` days, through today.
    case last(Int)
    /// From the first day through the last.
    case custom(ClosedRange<GarminDate>)

    /// The days shown, from the oldest to the newest.
    func dates(through today: GarminDate) -> ClosedRange<GarminDate> {
        switch self {
        case .last(let days): today.adding(days: 1 - max(days, 1))...today
        case .custom(let range): range
        }
    }

    /// How many days are shown.
    func dayCount(through today: GarminDate) -> Int {
        let dates = dates(through: today)
        return dates.lowerBound.days(to: dates.upperBound) + 1
    }

    /// `Last 30 days`, or the days picked: `1–15 Oct 2026`.
    var caption: String {
        switch self {
        case .last(let days):
            return String(localized: "Last \(days) days")
        case .custom(let range):
            let last = range.upperBound.startOfDay(in: .current).addingTimeInterval(12 * 3600)
            return (range.lowerBound.startOfDay(in: .current)..<last)
                .formatted(.interval.day().month(.abbreviated).year())
        }
    }
}

/// Picks the days a screen shows: segments for its usual spans and one for custom days, which
/// shows a date picker for the first and the last.
struct RangePicker: View {
    @Binding var choice: RangeChoice
    /// The usual spans, in days, with their short labels.
    let presets: [(days: Int, label: String)]
    /// The days that can be picked: through today, and as far back as there is data.
    let bounds: ClosedRange<GarminDate>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Range", selection: preset) {
                ForEach(presets, id: \.days) { preset in
                    Text(preset.label).tag(Int?.some(preset.days))
                }
                Text("Custom").tag(Int?.none)
            }
            .pickerStyle(.segmented)
            if case .custom(let range) = choice {
                HStack(spacing: 16) {
                    DatePicker(
                        "From",
                        selection: date(range.lowerBound) { .custom($0...range.upperBound) },
                        in: day(bounds.lowerBound)...day(range.upperBound),
                        displayedComponents: .date)
                    DatePicker(
                        "To", selection: date(range.upperBound) { .custom(range.lowerBound...$0) },
                        in: day(range.lowerBound)...day(bounds.upperBound),
                        displayedComponents: .date)
                }
                .datePickerStyle(.compact)
                .fixedSize()
            }
        }
    }

    /// The span picked, or `nil` for custom days; picking custom starts from the days shown.
    private var preset: Binding<Int?> {
        Binding {
            if case .last(let days) = choice {
                return days
            }
            return nil
        } set: { days in
            if let days {
                choice = .last(days)
            } else {
                choice = .custom(choice.dates(through: bounds.upperBound).clamped(to: bounds))
            }
        }
    }

    private func day(_ date: GarminDate) -> Date {
        date.startOfDay(in: .current)
    }

    private func date(
        _ value: GarminDate, _ choose: @escaping (GarminDate) -> RangeChoice
    )
        -> Binding<Date>
    {
        Binding {
            day(value)
        } set: { date in
            choice = choose(GarminDate(date))
        }
    }
}
