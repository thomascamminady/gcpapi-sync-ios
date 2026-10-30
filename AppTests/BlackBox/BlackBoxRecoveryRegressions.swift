import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

private func loads(_ values: [Double]) -> [TrainingLoad.Day] {
    AnalyticsBlackBox.dates(from: RecoveryScenario.start, count: values.count).enumerated().map {
        TrainingLoad.Day(date: $1, load: values[$0], fitness: 0, fatigue: 0)
    }
}

private func history(days: Int) -> HealthHistory {
    HealthHistory(
        days: AnalyticsBlackBox.dates(from: RecoveryScenario.start, count: days).map {
            DayHealth(date: $0, restingHeartRate: 50, hrv: 50, stress: 30)
        })
}

/// Documented behavior that the black-box tests found missing, kept so that it stays fixed.
@Suite("Recovery response: regressions")
struct RecoveryResponseBlackBoxRegressions {
    /// `hardDays`: "Training days with a load of at least ``threshold``."
    @Test(
        "The hardest share of training days count as hard; rest days do not count",
        arguments: [0.1, 0.2, 0.25, 0.5])
    func share(hardShare: Double) throws {
        // 100 training days with loads 1 to 100, shuffled, between 60 rest days.
        var random = BlackBoxRandom(seed: 5)
        var values = (1...100).map(Double.init) + Array(repeating: 0, count: 60)
        values.shuffle(using: &random)
        let days = loads(Array(repeating: 0, count: 40) + values)
        let response = RecoveryResponse(
            history: history(days: days.count), loads: days, hardShare: hardShare)
        let threshold = try #require(response.threshold)
        #expect(response.hardShare == hardShare)
        #expect(threshold > 0)
        #expect(response.hardDays == days.filter { $0.load >= threshold }.count)
        #expect(abs(Double(response.hardDays) - hardShare * 100) <= 1)
        #expect(threshold >= 100 * (1 - hardShare) - 1)
        #expect(threshold <= 100 * (1 - hardShare) + 2)
        #expect(response.restDays > 0)
        #expect(response.restDays <= 100)
    }

    /// "each block of consecutive hard training days is an event, from its first day";
    /// `hardDays`: "Training days with a load of at least ``threshold``."
    @Test("Two hard days in a row are both hard but one event")
    func consecutiveHardDays() throws {
        var values = Array(repeating: 0.0, count: 40)
        for pair in 0..<10 {
            var block = Array(repeating: 0.0, count: 40)
            block[0] = 300 + Double(2 * pair)
            block[1] = 301 + Double(2 * pair)
            for (index, offset) in [20, 23, 26].enumerated() {
                block[offset] = 10 + Double(3 * pair + index)
            }
            values += block
        }
        let days = loads(values)
        let response = RecoveryResponse(
            history: history(days: days.count), loads: days, hardShare: 0.38)
        let threshold = try #require(response.threshold)
        let hard = days.filter { $0.load >= threshold }.count
        #expect(hard >= 19)
        #expect(response.hardDays == hard)
        #expect(response.hardEvents == 10)
        let hrv = try #require(response.curves.first { $0.metric == .hrv })
        #expect(hrv.hard.first { $0.lag == 0 }?.events == response.hardEvents)
    }

    /// `threshold(_:share:)`: "of the loads that occur, the one whose share of days at or
    /// above it comes closest to `share`, so that tied loads all count or none does."
    @Test("Tied easy loads do not all become hard")
    func tiedLoads() throws {
        // 20 hard days and 30 easy ones of equal load, never two training days in a row: 40 %
        // of the training days are the 20 hard ones.
        var values = Array(repeating: 0.0, count: 40)
        for index in 0..<50 {
            values += [index < 20 ? 300 + Double(index) : 10, 0, 0]
        }
        let days = loads(values)
        let response = RecoveryResponse(
            history: history(days: days.count), loads: days, hardShare: 0.4)
        let threshold = try #require(response.threshold)
        #expect(days.filter { $0.load >= threshold }.count == 20)
        #expect(response.hardDays == 20)
    }

    /// `headline`: "`nil` when no metric does [respond clearly]."
    @Test("Without training there is no clearest response")
    func headlineWithoutTraining() {
        let response = RecoveryResponse(
            history: history(days: 100), loads: loads(Array(repeating: 0, count: 100)))
        #expect(response.headline == nil)
    }

    /// `headline`: "`nil` when no metric does [respond clearly]."
    @Test("Without any data there is no clearest response")
    func headlineWithoutData() {
        let response = RecoveryResponse(history: HealthHistory(days: []), loads: [])
        #expect(response.headline == nil)
    }

    /// `headline`: "`nil` when no metric does [respond clearly]."
    @Test("When nothing ever changes there is no clearest response")
    func headlineWithoutChange() {
        let response = RecoveryScenario().response()
        #expect(response.isSufficient)
        #expect(response.curves.allSatisfy { $0.hard.allSatisfy { !$0.isClear } })
        #expect(response.headline == nil)
    }
}
