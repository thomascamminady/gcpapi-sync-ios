import GCPAPISync
import SwiftUI

/// A screen the dashboard opens, besides activities and health metrics.
enum DeskRoute: Hashable {
    /// Fitness, fatigue and form in depth.
    case trainingLoad
    /// The activities of the month starting on a day, of one sport or all.
    case month(GarminDate, Sport?)
}

/// The dashboard of a wide window, on the iPad and the Mac: a week of activities as a table,
/// the months before it below, and a column of figures beside them.
struct DeskView: View {
    let training: TrainingModel
    let health: HealthModel
    /// Switches to the settings, which an iPad's tab bar leaves out; `nil` on the Mac, whose
    /// tab bar has them.
    let openSettings: (() -> Void)?
    /// How many weeks before this one the table shows.
    @State private var weeksBack = 0
    /// The sport of the monthly statistics, by raw value; empty for all sports.
    @SceneStorage("deskSport") private var sportName = Sport.running.rawValue
    @State private var width: CGFloat = 1200
    @Bindable private var preferences = Preferences.shared

    /// From this width on, the figures stand beside the tables instead of below them: an
    /// iPad in landscape with its sidebar, or a Mac window.
    private static let sideBySide: CGFloat = 1000
    /// The width of the column of figures.
    private static let panelWidth: CGFloat = 300

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Dashboard")
                .toolbarTitleDisplayMode(.inline)
                .navigationSubtitle(SyncStatus.text(training.lastUpdated))
                .toolbar {
                    if let openSettings {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Settings", systemImage: "gearshape", action: openSettings)
                        }
                    }
                }
                .navigationDestination(for: ActivityRoute.self, destination: activity)
                .navigationDestination(for: Route.self, destination: metric)
                .navigationDestination(for: DeskRoute.self, destination: desk)
                .task {
                    async let trained: Void = training.loadIfNeeded()
                    async let checked: Void = health.loadIfNeeded()
                    _ = await (trained, checked)
                }
                .refreshable {
                    async let trained: Void = training.load()
                    async let checked: Void = health.load()
                    _ = await (trained, checked)
                }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
    }

    @ViewBuilder
    private func activity(_ route: ActivityRoute) -> some View {
        if case .workout(let workout) = route, case .loaded(let data) = training.phase {
            WorkoutDetailView(
                workout: workout, zones: data.heartRateZones(for: workout.sport), model: training)
        }
    }

    @ViewBuilder
    private func metric(_ route: Route) -> some View {
        switch route {
        case .overview: OverviewDetailView(model: health)
        case .metric(let metric): MetricDetailView(metric: metric, model: health)
        }
    }

    @ViewBuilder
    private func desk(_ route: DeskRoute) -> some View {
        if case .loaded(let data) = training.phase {
            switch route {
            case .trainingLoad:
                TrainingLoadDetailView(days: data.load)
            case .month(let first, let sport):
                MonthActivities(first: first, sport: sport, workouts: data.history)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch training.phase {
        case .loading:
            ProgressView("Loading activities…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let data):
            layout(data)
        case .failed(let problem):
            ContentUnavailableView {
                Label(problem.title, systemImage: problem.symbol)
            } description: {
                Text(problem.message)
            } actions: {
                Button("Try Again") {
                    Task { await training.load() }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }

    private var healthHistory: HealthHistory? {
        if case .loaded(let history) = health.phase {
            return history
        }
        return nil
    }

    @ViewBuilder
    private func layout(_ data: TrainingData) -> some View {
        if width >= Self.sideBySide {
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    tables(data, isNarrow: width - Self.panelWidth < 900)
                        .padding(20)
                }
                Divider()
                ScrollView {
                    SidePanel(data: data, health: healthHistory)
                        .padding(20)
                }
                .frame(width: Self.panelWidth)
                .background(.background.secondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    tables(data, isNarrow: width < 900)
                    SidePanel(data: data, health: healthHistory, isGrid: true)
                }
                .padding(20)
            }
        }
    }

    private func tables(_ data: TrainingData, isNarrow: Bool) -> some View {
        let calendar = Calendar.app
        let today = data.loadHistory.last?.date ?? GarminDate.today()
        let start = TrainingWeek.weekStart(of: today, calendar: calendar).adding(
            days: -7 * weeksBack)
        let end = start.adding(days: 6)
        let week = data.history.filter { $0.date >= start && $0.date <= end }
        let earliest = data.loadHistory.first?.date ?? today
        let sport = Sport(rawValue: sportName)
        let workouts =
            sport.map { sport in data.history.filter { $0.sport == sport } } ?? data.history
        let months = ActivityTotals.months(
            workouts, count: Self.coveredMonths(from: earliest, through: today), through: today)
        return VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                WeekNavigator(
                    start: start, end: end, weeksBack: $weeksBack, canGoBack: start > earliest)
                ActivityLogTable(
                    workouts: week,
                    days: (0..<7).map { start.adding(days: $0) }.filter { $0 <= today }.reversed(),
                    isNarrow: isNarrow)
            }
            monthsSection(months, sport: sport, isNarrow: isNarrow)
        }
    }

    /// The months of one sport or all, with the choice of sport and shading.
    private func monthsSection(
        _ months: [ActivityTotals.Month], sport: Sport?, isNarrow: Bool
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Months")
                    .font(DeskStyle.title)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Toggle(isOn: $preferences.settings.shadesMonths) {
                    Label("Shade by Value", systemImage: "paintpalette")
                }
                .toggleStyle(.button)
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .help(Text("Shade by Value"))
                Picker("Sport", selection: $sportName) {
                    Text("All Sports").tag("")
                    ForEach(Sport.allCases) { sport in
                        Label(sport.title, systemImage: sport.symbol).tag(sport.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .buttonStyle(.glass)
                .fixedSize()
            }
            .controlSize(DeskStyle.controlSize)
            MonthlyStatisticsTable(
                months: months, sport: sport, isNarrow: isNarrow,
                isShaded: preferences.settings.shadesMonths)
        }
    }

    /// The months from the first whole one after `earliest` through the one containing `today`,
    /// at most seven: the months the loaded activities cover completely.
    static func coveredMonths(from earliest: GarminDate, through today: GarminDate) -> Int {
        let first = CalendarMonth.first(of: earliest)
        let whole = first == earliest ? first : CalendarMonth.adding(months: 1, to: first)
        let months = (today.year - whole.year) * 12 + today.month - whole.month + 1
        return min(max(months, 1), 7)
    }
}

/// The week the table shows, with buttons to the weeks before and after it.
private struct WeekNavigator: View {
    let start: GarminDate
    let end: GarminDate
    @Binding var weeksBack: Int
    let canGoBack: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(weeksBack == 0 ? "This Week" : weeksBack == 1 ? "Last Week" : "Week")
                .font(DeskStyle.title)
                .accessibilityAddTraits(.isHeader)
            Text(Self.range(start, end))
                .font(DeskStyle.font)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            HStack(spacing: 6) {
                Button("Previous Week", systemImage: "chevron.left") { weeksBack += 1 }
                    .labelStyle(.iconOnly)
                    .disabled(!canGoBack)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("This Week") { weeksBack = 0 }
                    .disabled(weeksBack == 0)
                Button("Next Week", systemImage: "chevron.right") { weeksBack -= 1 }
                    .labelStyle(.iconOnly)
                    .disabled(weeksBack == 0)
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .buttonStyle(.glass)
            .controlSize(DeskStyle.controlSize)
            .fixedSize()
        }
    }

    /// `26.10.–1.11.2026` or `10/26/2026 – 11/1/2026`, as the locale writes date ranges.
    static func range(_ start: GarminDate, _ end: GarminDate) -> String {
        // Up to the middle of the last day, so that the interval ends on it.
        let last = end.startOfDay(in: .current).addingTimeInterval(12 * 3600)
        return (start.startOfDay(in: .current)..<last)
            .formatted(.interval.day().month(.abbreviated).year())
    }
}
