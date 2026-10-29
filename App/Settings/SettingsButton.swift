import SwiftUI

/// The toolbar button that opens the settings.
struct SettingsButton: View {
    let lastUpdated: Date?
    @State private var isPresented = false

    var body: some View {
        Button("Settings", systemImage: "person.crop.circle") {
            isPresented = true
        }
        .sheet(isPresented: $isPresented) {
            SettingsView(lastUpdated: lastUpdated)
        }
    }
}
