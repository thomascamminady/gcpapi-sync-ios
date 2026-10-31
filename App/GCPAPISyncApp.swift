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
        #if DEBUG
            // Development builds connect with the key in GARMIN_PERSONAL_API_KEY, once, so that
            // it need not be pasted; the Keychain keeps it from then on.
            if !session.isSignedIn,
                let key = ProcessInfo.processInfo.environment["GARMIN_PERSONAL_API_KEY"]
            {
                Task { try? await session.connect(apiKey: key) }
            }
        #endif
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
        .commands {
            SettingsCommands()
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

/// The app menu's Settings… (⌘,), which opens the settings tab of the focused window.
struct SettingsCommands: Commands {
    @FocusedValue(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openSettings?() }
                .keyboardShortcut(",")
                .disabled(openSettings == nil)
        }
    }
}
