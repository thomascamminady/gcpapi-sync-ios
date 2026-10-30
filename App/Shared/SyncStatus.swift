import SwiftUI

/// When the data was last synced with Garmin, for navigation subtitles.
enum SyncStatus {
    static func text(_ lastUpdated: Date?) -> Text {
        guard let lastUpdated else { return Text("Syncing with Garmin…") }
        return Text("Synced \(lastUpdated, format: .relative(presentation: .named))")
    }
}
