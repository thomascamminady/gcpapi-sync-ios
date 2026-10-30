import Foundation
import GCPAPISync
import SwiftUI
import Testing

@testable import GCPAPISyncApp

/// How the recovery screens put their numbers into words.
@Suite struct BlackBoxRecoveryTextTests {
    /// The response to the demo's months of training.
    private func demoResponse(
        hardShare: Double? = nil, baselineDays: Int? = nil
    ) -> RecoveryResponse {
        let end = BlackBox.today
        let loads = TrainingData.sample(endingOn: end).loadHistory
        let history = HealthHistory.sample(endingOn: end, days: loads.count)
        return RecoveryResponse(
            history: history, loads: loads,
            hardShare: hardShare ?? RecoveryResponse.hardShare,
            baselineDays: baselineDays ?? RecoveryResponse.baselineDays
        )
    }

    // MARK: - Lags

    @Test func lagsAreTheDayBeforeTheDayAndThreeAfter() {
        #expect(RecoveryResponse.lags == [-1, 0, 1, 2, 3])
    }

    @Test func lagLabelsMatchTheDocumentation() {
        #expect(
            RecoveryResponse.lags.map(RecoveryChart.label) == ["Before", "Day", "+1", "+2", "+3"])
    }

    @Test func labelsAreDistinct() {
        let labels = RecoveryResponse.lags.map(RecoveryChart.label)
        #expect(Set(labels).count == labels.count)
    }

    // MARK: - Basis

    @Test func basisCountsTheDaysAndTheThreshold() throws {
        let response = demoResponse()
        try #require(response.hardDays > 0)
        let basis = RecoveryDetailView.basis(of: response)
        #expect(basis.hasPrefix("Based on "), "\(basis)")
        #expect(basis.contains("\(response.hardDays) hard day"), "\(basis)")
        #expect(basis.contains("\(response.restDays) rest day"), "\(basis)")
        #expect(basis.hasSuffix("."), "\(basis)")
        let threshold = try #require(response.threshold)
        let rounded = "load \(Int(threshold.rounded()))"
        let truncated = "load \(Int(threshold))"
        #expect(basis.contains(rounded) || basis.contains(truncated), "\(basis) \(threshold)")
        #expect(basis.contains("or more"), "\(basis)")
    }

    @Test func basisOfNoTrainingSaysSo() {
        let response = RecoveryResponse(history: HealthHistory(days: []), loads: [])
        #expect(response.hardDays == 0)
        #expect(!response.isSufficient)
        let basis = RecoveryDetailView.basis(of: response)
        #expect(!basis.isEmpty)
        #expect(!basis.contains("nil"))
    }

    @Test func aLargerShareOfHardDaysCountsMoreOfThem() {
        let few = demoResponse(hardShare: 0.1)
        let many = demoResponse(hardShare: 0.4)
        #expect(many.hardDays >= few.hardDays)
        #expect(RecoveryDetailView.basis(of: few).contains("\(few.hardDays) hard day"))
        #expect(RecoveryDetailView.basis(of: many).contains("\(many.hardDays) hard day"))
    }

    // MARK: - Method

    @Test func methodStatesTheUsersParameters() {
        let response = demoResponse()
        let method = RecoveryDetailView.method(of: response)
        #expect(!method.isEmpty)
        #expect(method.contains("\(response.baselineDays)"), "\(method)")
        let percent = Int((response.hardShare * 100).rounded())
        #expect(method.contains("\(percent)"), "\(method)")
    }

    @Test(arguments: [(0.25, 21), (0.15, 14), (0.3, 42)])
    func methodFollowsOtherParameters(hardShare: Double, baselineDays: Int) {
        let response = demoResponse(hardShare: hardShare, baselineDays: baselineDays)
        #expect(response.hardShare == hardShare)
        #expect(response.baselineDays == baselineDays)
        let method = RecoveryDetailView.method(of: response)
        #expect(method.contains("\(baselineDays)"), "\(method)")
        #expect(method.contains("\(Int((hardShare * 100).rounded()))"), "\(method)")
        #expect(method != RecoveryDetailView.method(of: demoResponse()))
    }
}
