import Charts
import GCPAPISync
import SwiftUI

/// Hours per week by sport, with this week's total.
struct VolumeCard: View {
    let weeks: [TrainingWeek]

    private var sports: [(sport: Sport, seconds: Double)] {
        Sport.allCases.compactMap { sport in
            let seconds = weeks.reduce(0) { $0 + ($1.seconds[sport] ?? 0) }
            return seconds > 0 ? (sport, seconds) : nil
        }
        .sorted { $0.seconds > $1.seconds }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Weekly Volume", symbol: "clock.fill", tint: .teal)
            if let week = weeks.last {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.hours(seconds: week.total))
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("this week")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    Text(summary(of: week))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            chart
                .frame(height: 160)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)]) {
                ForEach(sports, id: \.sport) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.sport.color).frame(width: 8, height: 8)
                        Text(item.sport.title)
                        Text(Format.hours(seconds: item.seconds)).foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func summary(of week: TrainingWeek) -> String {
        let average = weeks.dropLast().map(\.total).reduce(0, +) / Double(max(1, weeks.count - 1))
        let weeksBefore = weeks.count - 1
        let typical = Format.hours(seconds: average)
        return String(
            localized:
                "\(Format.activities(week.activityCount)) · \(weeksBefore)-week average \(typical)")
    }

    private var chart: some View {
        Chart(weeks) { week in
            ForEach(Sport.allCases) { sport in
                if let seconds = week.seconds[sport], seconds > 0 {
                    BarMark(
                        x: .value("Week", week.start.startOfDay(in: .current), unit: .weekOfYear),
                        y: .value("Hours", seconds / 3600),
                        width: .ratio(0.6)
                    )
                    .foregroundStyle(by: .value("Sport", sport.title))
                }
            }
        }
        // A fixed scale keeps each sport's color whichever sports appear.
        .chartForegroundStyleScale(
            domain: Sport.allCases.map(\.title), range: Sport.allCases.map(\.color)
        )
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text("\(hours.formatted()) h")
                    }
                }
            }
        }
    }
}
