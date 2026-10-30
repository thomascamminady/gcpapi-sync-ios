import SwiftUI

/// The open-source licenses of the app and of the code it includes.
struct LicensesView: View {
    /// A component, its license and the license's file in the app bundle.
    nonisolated struct Component: Identifiable, Sendable {
        let name: String
        let license: String
        let file: String

        var id: String { file }

        var text: String {
            Bundle.main.url(forResource: file, withExtension: "txt")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        }
    }

    nonisolated static let components = [
        Component(name: "GCPAPI Sync", license: "MIT", file: "GCPAPISyncApp"),
        Component(name: "gcpapi-sync-swift", license: "MIT", file: "GCPAPISync"),
        Component(name: "SwiftLog (Apple)", license: "Apache 2.0", file: "swift-log"),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.components) { component in
                    NavigationLink {
                        ScrollView {
                            Text(component.text)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                                .padding()
                        }
                        .navigationTitle(component.name)
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        LabeledContent(component.name, value: component.license)
                    }
                }
            } footer: {
                Text(
                    """
                    This app is free software under the MIT license. Maps © Apple and its data \
                    providers. Garmin and Garmin Connect are trademarks of Garmin Ltd.; this app \
                    is not affiliated with Garmin.
                    """
                )
            }
        }
        .navigationTitle("Licenses")
    }
}
