import Charts
import GCPAPISync
import SwiftUI

/// The other activities on this activity's route, and how pace developed on it.
struct SimilarRoutesCard: View {
    let workout: Workout
    let model: TrainingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: "Same Route",
                symbol: "point.topleft.down.to.point.bottomright.curvepath.fill",
                tint: workout.sport.color)
            content
        }
        .cardStyle()
    }

    @ViewBuilder private var content: some View {
        switch model.similar[workout.id] {
        case .found(let matches) where matches.isEmpty:
            Text("No other loaded activity was on this route.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .found(let matches):
            SimilarRoutesResults(workout: workout, matches: matches)
        case .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("Comparing routes…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let problem):
            Label(problem.message, systemImage: problem.symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            searchButton
        case nil:
            Text(
                """
                Find the other activities on this route and see how your pace on it \
                developed. This downloads up to ten recordings.
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            searchButton
        }
    }

    private var searchButton: some View {
        Button("Find Same Route", systemImage: "magnifyingglass") {
            Task { await model.findSimilarRoutes(to: workout) }
        }
        .buttonStyle(.glass)
    }
}

/// Pace on the route over time, and the activities on it.
private struct SimilarRoutesResults: View {
    let workout: Workout
    let matches: [Workout]

    var body: some View {
        let all = ([workout] + matches).sorted { $0.date < $1.date }
        let fastest = all.max { ($0.averageSpeed ?? 0) < ($1.averageSpeed ?? 0) }
        VStack(alignment: .leading, spacing: 12) {
            Text("\(Format.activities(matches.count)) on this route")
                .font(.headline)
            RouteProgressChart(workout: workout, all: all)
                .chartHeight(140)
            ForEach(all.reversed()) { item in
                NavigationLink(value: ActivityRoute.workout(item)) {
                    RouteVisitRow(
                        item: item, isCurrent: item.id == workout.id, isBest: item.id == fastest?.id
                    )
                }
                .disabled(item.id == workout.id)
            }
        }
    }
}

/// Pace (or speed) on each visit of the route, this one emphasized.
private struct RouteProgressChart: View {
    let workout: Workout
    let all: [Workout]

    var body: some View {
        Chart(all) { item in
            if let speed = item.averageSpeed {
                let date = item.date.startOfDay(in: .current)
                let value = TrackMeasure.plotted(speed: speed, sport: item.sport)
                LineMark(x: .value("Day", date, unit: .day), y: .value("Pace", value))
                    .foregroundStyle(item.sport.color.opacity(0.5))
                PointMark(x: .value("Day", date, unit: .day), y: .value("Pace", value))
                    .foregroundStyle(item.id == workout.id ? Color.primary : item.sport.color)
                    .symbolSize(item.id == workout.id ? 90 : 45)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let plotted = value.as(Double.self) {
                        Text(TrackMeasure.pace.axisLabel(plotted, sport: workout.sport))
                    }
                }
            }
        }
    }
}

/// A visit of the route: when, how long and how fast.
private struct RouteVisitRow: View {
    let item: Workout
    let isCurrent: Bool
    let isBest: Bool

    var body: some View {
        HStack {
            Text(
                item.date.startOfDay(in: .current),
                format: .dateTime.day().month(.abbreviated).year())
            if isBest {
                StatusBadge(label: String(localized: "Best"), color: ColorRole.status(.good).color)
            }
            Spacer()
            Text(Format.clock(seconds: item.duration))
            if let speed = item.averageSpeed {
                Text(Format.pace(metresPerSecond: speed, sport: item.sport))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.monospacedDigit())
        .fontWeight(isCurrent ? .semibold : .regular)
    }
}
