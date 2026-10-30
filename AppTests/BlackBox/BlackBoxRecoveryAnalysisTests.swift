import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// HRV 20 % lower on the training day and 16 % lower the day after.
nonisolated private func hrvDrop(_ metric: OverviewMetric, _ lag: Int) -> Double {
    guard metric == .hrv else { return 1 }
    return [0: 0.8, 1: 0.84][lag] ?? 1
}

/// Resting heart rate 10 % higher the day after training only.
nonisolated private func heartRateRise(_ metric: OverviewMetric, _ lag: Int) -> Double {
    metric == .restingHeartRate && lag == 1 ? 1.1 : 1
}

@Suite("Recovery response: the superposed epoch analysis")
struct BlackBoxRecoveryAnalysisTests {
    private func curve(
        _ response: RecoveryResponse, _ metric: OverviewMetric
    ) throws
        -> RecoveryResponse.Curve
    {
        try #require(response.curves.first { $0.metric == metric })
    }

    @Test("One curve per metric, each with a point per lag")
    func shape() {
        let response = RecoveryScenario(noise: [.hrv: 2]).response()
        #expect(response.curves.map(\.metric) == RecoveryResponse.metrics)
        for curve in response.curves {
            #expect(curve.id == curve.metric)
            #expect(curve.hard.map(\.lag) == RecoveryResponse.lags)
            #expect(curve.rest.map(\.lag) == RecoveryResponse.lags)
            #expect(curve.rest.allSatisfy { $0.events <= response.restDays })
            #expect(curve.hard.allSatisfy { $0.events <= response.hardDays })
        }
    }

    @Test("A planted HRV drop is found, clear, and recovered from after two days")
    func plantedHRV() throws {
        let scenario = RecoveryScenario(effect: hrvDrop)
        let response = scenario.response()
        #expect(response.isSufficient)
        // A quarter of the training days are hard: the later three quarters of the planted.
        #expect(response.hardDays <= scenario.planted.count)
        #expect(response.hardDays * 4 >= scenario.planted.count * 3 - 4)
        let hrv = try curve(response, .hrv)
        let byLag = Dictionary(uniqueKeysWithValues: hrv.hard.map { ($0.lag, $0) })
        let dayOf = try #require(byLag[0])
        let dayAfter = try #require(byLag[1])
        #expect(abs(dayOf.mean + 20) < 2.5)
        #expect(abs(dayAfter.mean + 16) < 2.5)
        #expect(dayOf.isClear && dayAfter.isClear)
        for lag in [-1, 2, 3] {
            let point = try #require(byLag[lag])
            #expect(abs(point.mean) < 2.5)
        }
        #expect(hrv.peak?.lag == 0)
        #expect(hrv.recoveredAfter == 2)
        #expect(response.headline?.metric == .hrv)
        // The other metrics never changed.
        for metric in [OverviewMetric.restingHeartRate, .sleepScore, .stress] {
            #expect(try curve(response, metric).hard.allSatisfy { $0.mean == 0 && !$0.isClear })
        }
    }

    @Test("A delayed rise in resting heart rate leads when HRV shows nothing")
    func plantedHeartRate() throws {
        let scenario = RecoveryScenario(effect: heartRateRise)
        let response = scenario.response()
        let heartRate = try curve(response, .restingHeartRate)
        let byLag = Dictionary(uniqueKeysWithValues: heartRate.hard.map { ($0.lag, $0) })
        #expect(abs((byLag[1]?.mean ?? 0) - 10) < 2.5)
        #expect(byLag[1]?.isClear == true)
        #expect(byLag[0]?.isClear == false)
        #expect(heartRate.peak?.lag == 1)
        #expect(heartRate.recoveredAfter == 2)
        #expect(response.headline?.metric == .restingHeartRate)
        #expect(try curve(response, .hrv).hard.allSatisfy { !$0.isClear })
    }

    @Test("HRV leads whenever it responds, even when another metric responds more")
    func hrvFirst() throws {
        let scenario = RecoveryScenario { metric, lag in
            switch (metric, lag) {
            case (.hrv, 1): return 0.92
            case (.restingHeartRate, 0), (.restingHeartRate, 1): return 1.3
            default: return 1
            }
        }
        let response = scenario.response()
        #expect(try curve(response, .hrv).hard.contains { $0.lag == 1 && $0.isClear })
        #expect(response.headline?.metric == .hrv)
    }

    @Test("Constant metrics never change, so nothing is clear and nothing leads")
    func constant() {
        let response = RecoveryScenario().response()
        #expect(response.isSufficient)
        for curve in response.curves {
            for point in curve.hard + curve.rest {
                #expect(point.mean == 0)
                #expect(point.margin == 0)
                #expect(!point.isClear)
            }
        }
    }

    @Test("Pure noise shows no change", arguments: [UInt64(3), 17, 2026])
    func noise(seed: UInt64) {
        let scenario = RecoveryScenario(
            seed: seed, noise: [.hrv: 5, .restingHeartRate: 4, .sleepScore: 8, .stress: 2])
        let response = scenario.response()
        var clear = 0
        for curve in response.curves {
            for point in curve.hard {
                #expect(abs(point.mean) < 4, "\(curve.metric) at lag \(point.lag)")
                #expect(point.margin > 0)
                clear += point.isClear ? 1 : 0
            }
        }
        #expect(clear <= 4)
        if let headline = response.headline {
            #expect(abs(headline.peak?.mean ?? 0) < 4)
        }
    }

    @Test(
        "Means, events and margins follow the documented analysis",
        arguments: [UInt64(1), 9, 41, 400])
    func oracle(seed: UInt64) {
        let scenario = RecoveryScenario(
            seed: seed, noise: [.hrv: 4, .restingHeartRate: 3, .sleepScore: 6, .stress: 5],
            outliers: 0.04, missing: 0.08, effect: hrvDrop)
        RecoveryCheck.expectMatchesOracle(
            scenario.response(), scenario: scenario, baselineDays: RecoveryResponse.baselineDays)
    }

    @Test(
        "The usual level is the median of the given number of days before",
        arguments: [7, 14, 28, 42])
    func baselineWindow(days: Int) {
        let scenario = RecoveryScenario(
            count: 320, lead: 60, noise: [.hrv: 2, .stress: 2],
            drift: [.hrv: 0.08, .restingHeartRate: -0.03], outliers: 0.05, effect: hrvDrop)
        let response = scenario.response(baselineDays: days)
        #expect(response.baselineDays == days)
        RecoveryCheck.expectMatchesOracle(response, scenario: scenario, baselineDays: days)
    }

    @Test("Outliers before an event do not move its usual level")
    func medianNotMean() throws {
        // Every value is 50 but for one 500 in each baseline; the median stays at 50.
        var scenario = RecoveryScenario(effect: hrvDrop)
        for event in scenario.planted {
            scenario.values[.hrv]?[event - 5] = 500
        }
        let response = scenario.response()
        let hrv = try curve(response, .hrv)
        let dayOf = try #require(hrv.hard.first { $0.lag == 0 })
        #expect(AnalyticsBlackBox.isClose(dayOf.mean, -20, tolerance: 1e-9))
    }

    @Test("Scaling a metric leaves its percentage changes alone")
    func scaleInvariance() throws {
        let scenario = RecoveryScenario(noise: [.hrv: 3], effect: hrvDrop)
        var doubled = scenario
        doubled.values[.hrv] = scenario.values[.hrv]?.map { $0.map { $0 * 2 } }
        let base = try curve(scenario.response(), .hrv)
        let scaled = try curve(doubled.response(), .hrv)
        for (point, other) in zip(base.hard, scaled.hard) {
            #expect(AnalyticsBlackBox.isClose(point.mean, other.mean, tolerance: 1e-9))
            #expect(AnalyticsBlackBox.isClose(point.margin, other.margin, tolerance: 1e-9))
            #expect(point.events == other.events)
        }
    }

    @Test("More events narrow the confidence interval")
    func moreEventsNarrower() throws {
        let short = RecoveryScenario(count: 160, noise: [.hrv: 4], effect: hrvDrop)
        let long = RecoveryScenario(count: 680, noise: [.hrv: 4], effect: hrvDrop)
        let few = try #require(try curve(short.response(), .hrv).hard.first { $0.lag == 0 })
        let many = try #require(try curve(long.response(), .hrv).hard.first { $0.lag == 0 })
        #expect(many.events > few.events * 3)
        #expect(many.margin < few.margin)
    }

    @Test("Events count only the days with a value")
    func eventsWithValues() throws {
        var scenario = RecoveryScenario(noise: [.hrv: 1], effect: hrvDrop)
        // The latest planted days have the highest loads, so they are hard.
        let removed = scenario.planted.suffix(5)
        for event in removed {
            scenario.values[.hrv]?[event + 2] = nil
        }
        let response = scenario.response()
        let hrv = try curve(response, .hrv)
        let lag1 = try #require(hrv.hard.first { $0.lag == 1 })
        let lag2 = try #require(hrv.hard.first { $0.lag == 2 })
        #expect(lag2.events == lag1.events - removed.count)
    }

    @Test("A usual level needs the minimum number of values before the event")
    func minimumBaseline() throws {
        let minimum = RecoveryResponse.minimumBaseline
        for (present, counted) in [(minimum, true), (minimum - 1, false)] where present >= 0 {
            var scenario = RecoveryScenario(count: 400, spacing: 40, lead: 40)
            let events = Set(scenario.planted)
            for day in scenario.loads.indices {
                let keep = events.contains { event in
                    (event - present..<event + 4).contains(day)
                }
                if !keep {
                    scenario.values[.hrv]?[day] = nil
                }
            }
            // Three easy days far from each hard day, without HRV: hard days are a quarter of
            // the training days, so the hardest fifth are all planted ones.
            scenario.loads = scenario.loads.map { $0 >= 300 ? $0 : 0 }
            for event in scenario.planted {
                for offset in 20..<23 where event + offset < scenario.loads.count {
                    scenario.loads[event + offset] = Double(offset)
                }
            }
            let response = scenario.response(hardShare: 0.2)
            let hrv = try curve(response, .hrv)
            let dayOf = hrv.hard.first { $0.lag == 0 }
            #expect(response.hardDays > 0)
            if counted {
                #expect(dayOf?.events == response.hardDays, "\(present) values")
            } else {
                #expect((dayOf?.events ?? 0) == 0, "\(present) values")
            }
        }
    }
}
