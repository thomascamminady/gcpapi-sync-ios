import GCPAPISync
import MapKit
import SwiftUI

/// Where you went: the routes of the activities of a range of days on one map, by default the
/// last week, each opening its activity.
struct ActivityMapView: View {
    let model: TrainingModel
    let data: TrainingData
    @State private var range = RangeChoice.last(7)
    /// The sport shown, by raw value; empty for all.
    @SceneStorage("activityMapSport") private var sportName = ""
    @SceneStorage("activityMapColoring") private var coloring = Coloring.sport
    @State private var selected: Workout?
    @State private var position = MapCameraPosition.automatic

    /// What the routes' colors say.
    enum Coloring: String, CaseIterable {
        case sport
        /// The color map, from the range's first day to its last.
        case date
    }

    private var today: GarminDate {
        data.loadHistory.last?.date ?? GarminDate.today()
    }

    /// The activities of the range and sport that have a route.
    private var workouts: [Workout] {
        let dates = range.dates(through: today)
        let sport = Sport(rawValue: sportName)
        return data.history.filter { workout in
            dates.contains(workout.date) && workout.startPoint != nil
                && (sport == nil || workout.sport == sport)
        }
    }

    var body: some View {
        let workouts = workouts
        Map(position: $position) {
            ForEach(workouts) { workout in
                if let route = model.route(of: workout) {
                    MapPolyline(coordinates: route.map(\.coordinate))
                        .stroke(
                            color(workout),
                            style: StrokeStyle(
                                lineWidth: selected?.id == workout.id ? 6 : 3, lineCap: .round,
                                lineJoin: .round))
                }
            }
            ForEach(workouts) { workout in
                if let start = workout.startPoint {
                    Annotation(workout.name, coordinate: start.coordinate, anchor: .center) {
                        Button {
                            selected = workout
                        } label: {
                            Circle()
                                .fill(color(workout))
                                .stroke(.white, lineWidth: 2)
                                .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(workout.name))
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(RouteMap.style(Preferences.shared.settings.mapStyle))
        .safeAreaInset(edge: .top) {
            controls(loading: workouts.filter { model.route(of: $0) == nil }.count)
        }
        .safeAreaInset(edge: .bottom) {
            if let selected {
                SelectedActivity(workout: selected) { self.selected = nil }
            }
        }
        .task(id: workouts.map(\.id)) {
            selected = nil
            position = .automatic
            await model.loadTracks(for: workouts)
            // Frame the routes once they are drawn.
            position = .automatic
        }
    }

    private func color(_ workout: Workout) -> Color {
        switch coloring {
        case .sport:
            return workout.sport.color
        case .date:
            let dates = range.dates(through: today)
            let span = Double(max(dates.lowerBound.days(to: dates.upperBound), 1))
            return Preferences.shared.valueColor(
                Double(dates.lowerBound.days(to: workout.date)) / span)
        }
    }

    /// The range, the sport and the coloring, with how many routes are still loading.
    private func controls(loading: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            RangePicker(
                choice: $range,
                presets: HistoryRange.allCases.map { ($0.days, $0.label) },
                bounds: (data.history.last?.date ?? today)...today)
            filters(loading: loading)
            if coloring == .date {
                ValueLegend(
                    title: String(localized: "Date"),
                    low: Self.day(range.dates(through: today).lowerBound),
                    high: Self.day(range.dates(through: today).upperBound))
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .readableWidth(720)
    }

    /// The sport and the coloring, with how many routes are still loading.
    private func filters(loading: Int) -> some View {
        HStack(spacing: 8) {
            Picker("Sport", selection: $sportName) {
                Text("All Sports").tag("")
                ForEach(Sport.allCases) { sport in
                    Label(sport.title, systemImage: sport.symbol).tag(sport.rawValue)
                }
            }
            .pickerStyle(.menu)
            Picker("Colors", selection: $coloring) {
                Text("Sport").tag(Coloring.sport)
                Text("Date").tag(Coloring.date)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            Spacer(minLength: 0)
            if loading > 0 {
                ProgressView()
                    .controlSize(.small)
                Text("^[\(loading) route](inflect: true) loading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// `12 Oct`.
    static func day(_ date: GarminDate) -> String {
        date.startOfDay(in: .current).formatted(.dateTime.day().month(.abbreviated))
    }
}

/// The activity whose start was tapped, opening it.
private struct SelectedActivity: View {
    let workout: Workout
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: ActivityRoute.workout(workout)) {
                HStack(spacing: 12) {
                    Image(systemName: workout.sport.symbol)
                        .font(.title3)
                        .foregroundStyle(workout.sport.color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name)
                            .font(.headline)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .readableWidth(720)
    }

    private var summary: String {
        let date = (workout.start ?? workout.date.startOfDay(in: .current)).formatted(
            .dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let figures = [
            workout.distance.map(Format.distance), Format.clock(seconds: workout.duration),
        ]
        return ([date] + figures.compactMap(\.self)).joined(separator: " · ")
    }
}
