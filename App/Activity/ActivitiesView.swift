import GCPAPISync
import SwiftUI

/// A screen the activities tab opens.
enum ActivityRoute: Hashable {
    case workout(Workout)
}

/// How the activities tab shows activities.
enum ActivityLayout: String {
    case list
    case calendar
    case map
}

/// The activities tab: every activity of the last 90 days as a list, month by month, or as
/// routes on a map.
struct ActivitiesView: View {
    let model: TrainingModel
    @SceneStorage("activityLayout") private var layout = ActivityLayout.list

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Activities")
                .navigationDestination(for: ActivityRoute.self) { route in
                    if case .workout(let workout) = route, case .loaded(let data) = model.phase {
                        WorkoutDetailView(
                            workout: workout, zones: data.heartRateZones(for: workout.sport),
                            model: model)
                    }
                }
                .navigationSubtitle(SyncStatus.text(model.lastUpdated))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Picker("Layout", selection: $layout) {
                            Label("List", systemImage: "list.bullet").tag(ActivityLayout.list)
                            Label("Calendar", systemImage: "calendar").tag(ActivityLayout.calendar)
                            Label("Map", systemImage: "map").tag(ActivityLayout.map)
                        }
                        .pickerStyle(.segmented)
                        .labelStyle(.iconOnly)
                    }
                }
                .task { await model.loadIfNeeded() }
                .refreshable { await model.load() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("Loading activities…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let data):
            switch layout {
            case .list: ActivityListView(data: data)
            case .calendar: ActivityCalendarView(model: model)
            case .map: ActivityMapView(model: model, data: data)
            }
        case .failed(let problem):
            ContentUnavailableView {
                Label(problem.title, systemImage: problem.symbol)
            } description: {
                Text(problem.message)
            } actions: {
                Button("Try Again") {
                    Task { await model.load() }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}

/// The last seven days at a glance: activities, time and distance.
struct RecentSummary: View {
    let workouts: [Workout]

    var body: some View {
        let distance = workouts.compactMap(\.distance).reduce(0, +)
        HStack(alignment: .top, spacing: 24) {
            Figure(title: "Activities", value: workouts.count.formatted())
            Figure(
                title: "Time", value: Format.hours(seconds: workouts.reduce(0) { $0 + $1.duration })
            )
            if distance > 0 {
                Figure(title: "Distance", value: Format.distance(metres: distance))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private struct Figure: View {
        let title: LocalizedStringKey
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.bold).monospacedDigit())
            }
        }
    }
}
