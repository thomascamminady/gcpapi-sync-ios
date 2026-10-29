import SwiftUI

/// Connect first; then the week.
struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .signedOut:
                ConnectView()
                    .transition(.opacity)
            case .signedIn(let client):
                WeekView(model: HealthModel(client: client))
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: session.isSignedIn)
    }
}
