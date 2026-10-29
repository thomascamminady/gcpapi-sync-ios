import SwiftUI

@main
struct GCPAPISyncApp: App {
    @State private var session: Session

    init() {
        let session = Session()
        // UI tests and screenshots start in the demo with `-demo`.
        if ProcessInfo.processInfo.arguments.contains("-demo"), !session.isSignedIn {
            session.startDemo()
        }
        _session = State(initialValue: session)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }
}
