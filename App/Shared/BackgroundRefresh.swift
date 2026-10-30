import BackgroundTasks
import Foundation
import GCPAPISync

/// Refreshes the saved health and training data while the app is in the background, so it
/// opens up to date. iOS decides when; the app asks for about once an hour.
nonisolated enum BackgroundRefresh {
    static let identifier = "dev.camminady.gcpapi-sync.refresh"

    /// Ask iOS to refresh in about an hour.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = .now.addingTimeInterval(3600)
        // Only fails when background refresh is off for the app, or in the simulator.
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Load the dashboard's week and the training data and save them, unless the user
    /// turned background refresh off or is not connected.
    @concurrent
    static func run(
        settings: Settings, client: GarminClient?, store: SnapshotStore, today: GarminDate
    ) async {
        guard settings.refreshesInBackground, let client else { return }
        schedule()
        async let week = HealthLoader.load(
            from: client, endingOn: today, days: HealthModel.dashboardDays)
        async let training = TrainingLoader.load(
            from: client, endingOn: today, analysis: settings.analysis)
        if let week = try? await week {
            try? store.save(week, as: HealthModel.snapshot)
        }
        if let training = try? await training {
            try? store.save(training, as: TrainingModel.snapshot)
        }
    }
}
