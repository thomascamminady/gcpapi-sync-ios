import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// An activity's recording to share, fetched only when it is shared.
struct RecordingFile: Transferable {
    enum Format {
        case fit
        case gpx
    }

    let workout: Workout
    let format: Format
    let model: TrainingModel

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .data) { file in
            try await file.data()
        }
        .suggestedFileName { file in
            "\(file.workout.date) \(file.workout.name).\(file.format == .fit ? "fit" : "gpx")"
        }
    }

    private func data() async throws -> Data {
        guard let recording = try await model.recording(for: workout) else {
            throw CocoaError(.fileNoSuchFile)
        }
        switch format {
        case .fit:
            return recording
        case .gpx:
            let decoded = try FITActivity(decoding: recording)
            return Data(Exporter.gpx(decoded, name: workout.name).utf8)
        }
    }
}
