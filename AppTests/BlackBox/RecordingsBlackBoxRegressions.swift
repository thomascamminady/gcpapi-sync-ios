import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// Documented behavior that the black-box tests found missing, kept so that it stays fixed.
@Suite("Recordings: regressions", .serialized)
struct RecordingsBlackBoxRegressions {
    // From the ActivityTrack sample tests. `Sample` is "the average of the records in a slice
    // of time", `elapsed` its "seconds of timer time since the start", and `duration` the
    // "seconds of timer time from the first record to the last": no sample lies after the
    // last record.
    @Test(
        "Samples are bounded and ordered",
        arguments: [1, 2, 3, 10, 100, 1000, 5000, 20_000, 40_000])
    func samplesBounded(count: Int) {
        let track = RecordingRun(seconds: count).track()
        #expect(track.duration == Double(count - 1))
        #expect(track.samples.count <= ActivityTrack.maxSamples)
        if count >= 2 {
            #expect(track.samples.count >= 2)
        }
        let elapsed = track.samples.map(\.elapsed)
        #expect(zip(elapsed, elapsed.dropFirst()).allSatisfy { $0 < $1 })
        #expect(elapsed.allSatisfy { $0 >= 0 && $0 <= track.duration + 1e-9 })
        #expect(Set(track.samples.map(\.id)).count == track.samples.count)
    }

    // From the ActivityTrack route tests. `maxPoints`: "The most route points the map gets."
    @Test("The route is bounded and ordered", arguments: [2, 10, 1000, 30_000])
    func routeBounded(count: Int) {
        let track = RecordingRun(seconds: count).track()
        let route = track.route
        #expect(route.count <= ActivityTrack.maxPoints)
        #expect(route.count <= count)
        #expect(route.count >= 2)
        let elapsed = route.map(\.elapsed)
        #expect(zip(elapsed, elapsed.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(elapsed.allSatisfy { $0 >= 0 && $0 <= track.duration + 1e-9 })
        #expect(route.allSatisfy { abs($0.latitude - 47) <= 0.01 + 1e-9 })
        #expect(route.allSatisfy { abs($0.longitude - 8) <= 0.01 + 1e-9 })
        #expect(route.allSatisfy { $0.heartRate == 150 })
    }

    // From the TrackChart.domain tests. "The range of the middle 96% of `values`, padded":
    // of two values neither is an outlier.
    @Test("Two values")
    func twoValues() {
        let domain = TrackChart.domain([0, 10])
        #expect(domain.lowerBound <= 1 && domain.upperBound >= 9, "\(domain)")
    }

    // From the strength tests. `ExerciseCategory.name(_:) -> String?` names "Garmin's
    // exercise categories of strength sets, from the FIT profile"; other numbers have none.
    // The argument -1 crashes the test process (index out of range).
    @Test("Unknown categories have no name", arguments: [nil, -1, 1000, 10_000] as [Int?])
    func unknown(category: Int?) {
        #expect(ExerciseCategory.name(category) == nil)
    }

    // From the strength tests. `logged`: "The active sets with something to show"; the card
    // shows "Strength training sets: exercise, repetitions and weight", so a set with a
    // weight has something to show.
    @Test("Logged sets are the active ones with something to show")
    func logged() {
        let squat = FITActivity.ExerciseSet(
            duration: 40, repetitions: 8, weight: 80, isActive: true, category: 28)
        let rest = FITActivity.ExerciseSet(duration: 90, isActive: false)
        let restWithReps = FITActivity.ExerciseSet(repetitions: 3, isActive: false)
        let press = FITActivity.ExerciseSet(repetitions: 10, isActive: true, category: 0)
        let weighted = FITActivity.ExerciseSet(weight: 20, isActive: true)
        let nothing = FITActivity.ExerciseSet(isActive: true)
        let sets = [squat, rest, press, restWithReps, nothing, weighted, rest]
        #expect(SetsCard.logged(sets) == [squat, press, weighted])
        #expect(SetsCard.logged([]).isEmpty)
        #expect(SetsCard.logged([rest, restWithReps, nothing]).isEmpty)
    }
}
