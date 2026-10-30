import SwiftUI

/// Connect first; then health and training.
struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .signedOut:
                ConnectView()
                    .transition(.opacity)
            case .signedIn(let client):
                MainView(
                    client: client,
                    snapshots: session.isDemo ? nil : session.snapshots,
                    recordings: session.isDemo ? nil : session.recordings
                )
                .transition(.opacity)
            }
        }
        .animation(.smooth, value: session.isSignedIn)
    }
}
