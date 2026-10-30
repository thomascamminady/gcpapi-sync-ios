import GCPAPISync
import SwiftUI

@main
struct GCPAPISyncApp: App {
    @State private var session: Session

    init() {
        let session = Session(snapshots: .standard, recordings: .standard)
        // UI tests and screenshots start in the demo with `-demo`.
        if ProcessInfo.processInfo.arguments.contains("-demo"), !session.isSignedIn {
            session.startDemo()
        }
        _session = State(initialValue: session)
    }

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, session.isSignedIn, !session.isDemo {
                BackgroundRefresh.schedule()
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            let settings = await Preferences.shared.settings
            await BackgroundRefresh.run(
                settings: settings, client: Session.storedClient(), store: .standard,
                today: .today())
        }
    }
}
