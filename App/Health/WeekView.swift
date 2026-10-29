import GCPAPISync
import SwiftUI

/// The signed-in screen: the last seven days of health data.
struct WeekView: View {
    @State private var model: WeekModel
    @State private var showsSettings = false
    @Environment(Session.self) private var session

    init(model: WeekModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Last 7 Days")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Settings", systemImage: "person.crop.circle") {
                            showsSettings = true
                        }
                    }
                }
                .sheet(isPresented: $showsSettings) {
                    SettingsView(lastUpdated: model.lastUpdated)
                }
                .task { await model.load() }
                .refreshable { await model.load() }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            DashboardView(week: .sample(endingOn: .today()))
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityLabel("Loading")
        case .loaded(let week):
            DashboardView(week: week, refreshProblem: model.refreshProblem)
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
                if problem == .keyRejected {
                    Button("Use a Different Key", role: .destructive) { session.signOut() }
                }
            }
        }
    }
}

#Preview("Loaded") {
    WeekView(model: WeekModel { day in .sample(endingOn: day) })
        .environment(Session.preview)
}

#Preview("Failed") {
    WeekView(model: WeekModel { _ in throw Problem.offline })
        .environment(Session.preview)
}
