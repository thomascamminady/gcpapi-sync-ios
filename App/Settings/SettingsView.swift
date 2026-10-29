import GCPAPISync
import SwiftUI

/// The account and the app's details.
struct SettingsView: View {
    let lastUpdated: Date?
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDisconnect = false

    private static let sourceCode = URL(
        string: "https://github.com/thomascamminady/gcpapi-sync-ios")

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Garmin") {
            LabeledContent("Account", value: session.isDemo ? "Sample data" : "Connected")
            if let lastUpdated {
                LabeledContent("Updated") {
                    Text(lastUpdated, format: .relative(presentation: .named))
                }
            }
            Button(session.isDemo ? "Leave Sample Data" : "Disconnect", role: .destructive) {
                confirmsDisconnect = true
            }
            .confirmationDialog(
                "Disconnect from Garmin?", isPresented: $confirmsDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    dismiss()
                    session.signOut()
                }
            } message: {
                Text(
                    "Your API key is removed from this iPhone. Your data on Garmin is not affected."
                )
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            LabeledContent("GCPAPISync", value: packageVersion)
            if let url = Self.sourceCode {
                Link("Source Code", destination: url)
            }
        } header: {
            Text("About")
        } footer: {
            Text(
                """
                A personal, open-source project. Not affiliated with or endorsed by Garmin or \
                Wahoo Fitness. Garmin and Garmin Connect are trademarks of Garmin Ltd.
                """
            )
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView(lastUpdated: .now)
        .environment(Session.preview)
}
