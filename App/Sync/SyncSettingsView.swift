import SwiftUI
import UniformTypeIdentifiers

/// Choosing the folder the devices sync their routes and settings through.
struct SyncSettingsView: View {
    @Environment(DeviceSync.self) private var sync
    @State private var isChoosing = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder", value: sync.folderName ?? String(localized: "None"))
                Button(sync.folderName == nil ? "Choose Folder…" : "Choose Another Folder…") {
                    isChoosing = true
                }
                if sync.folderName != nil {
                    syncing
                }
                if let problem = sync.problem {
                    Label(problem.message, systemImage: problem.symbol)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text(
                    """
                    Planned routes and settings are kept in one file in this folder. Choose the \
                    same folder, in iCloud Drive for instance, on every device: they update each \
                    other whenever the app opens or something changes. Garmin's data needs no \
                    syncing, each device fetches it; the calendar and background refresh stay \
                    with each device.
                    """)
            }
        }
        .navigationTitle("Sync Between Devices")
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result {
                Task { await sync.choose(folder) }
            }
        }
    }

    /// Syncing now, when it last happened, and stopping.
    @ViewBuilder private var syncing: some View {
        Button("Sync Now") {
            Task { await sync.sync() }
        }
        .disabled(sync.isSyncing)
        if let lastSynced = sync.lastSynced {
            LabeledContent("Synced") {
                Text(lastSynced, format: .relative(presentation: .named))
            }
        }
        Button("Stop Syncing", role: .destructive) { sync.stop() }
    }
}
