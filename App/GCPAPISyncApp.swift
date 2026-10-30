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

    /// On the Mac, windows no smaller than the dashboard's tables need.
    private static func limitWindowSize() {
        #if targetEnvironment(macCatalyst)
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 600)
            }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { Self.limitWindowSize() }
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
