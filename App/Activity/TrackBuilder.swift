import Foundation

/// Decodes and analyzes recordings away from the main actor; long rides have tens of
/// thousands of records.
nonisolated enum TrackBuilder {
    @concurrent
    static func track(
        from data: Data, sport: Sport, splitLength: Double
    ) async throws(FITError)
        -> ActivityTrack
    {
        ActivityTrack(try FITActivity(decoding: data), sport: sport, splitLength: splitLength)
    }
}
