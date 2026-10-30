import Foundation
import GCPAPISync
import Testing

@testable import GCPAPISyncApp

/// The days of `loads`, one load per day from the reference date.
private func series(
    _ loads: [Double], fitnessDays: Double = TrainingLoad.fitnessDays,
    fatigueDays: Double = TrainingLoad.fatigueDays
) throws -> [TrainingLoad.Day] {
    let first = AnalyticsBlackBox.reference
    return TrainingLoad.days(
        try AnalyticsBlackBox.workouts(loads, from: first), from: first,
        through: first.adding(days: loads.count - 1), fitnessDays: fitnessDays,
        fatigueDays: fatigueDays)
}

/// `count` loads of a seeded generator, about a third of them rest days.
private func randomLoads(seed: UInt64, count: Int) -> [Double] {
    var random = BlackBoxRandom(seed: seed)
    return (0..<count).map { _ in
        random.uniform(0...1) < 0.35 ? 0 : random.uniform(10...250).rounded()
    }
}

@Suite("Training load: days and exponential averages")
struct BlackBoxTrainingLoadTests {
    @Test("Documented windows: six weeks of fitness, one week of fatigue")
    func documentedWindows() {
        #expect(TrainingLoad.fitnessDays == 42)
        #expect(TrainingLoad.fatigueDays == 7)
    }

    @Test("One day per date from first through last", arguments: [1, 2, 7, 31, 210])
    func oneDayPerDate(count: Int) {
        let first = GarminDate.day("2024-02-20")
        let last = first.adding(days: count - 1)
        let days = TrainingLoad.days([], from: first, through: last)
        #expect(days.map(\.date) == AnalyticsBlackBox.dates(from: first, count: count))
        #expect(days.map(\.id) == days.map(\.date))
    }

    @Test("Without workouts every value is zero and there is no form share")
    func noWorkouts() {
        let days = TrainingLoad.days(
            [], from: AnalyticsBlackBox.reference,
            through: AnalyticsBlackBox.reference.adding(days: 59))
        for day in days {
            #expect(day.load == 0)
            #expect(day.fitness == 0)
            #expect(day.fatigue == 0)
            #expect(day.form == 0)
            #expect(day.formShare == nil)
            #expect(day.zone == nil)
        }
    }

    @Test("A day's load is the sum of its activities' training load")
    func loadIsSumOfActivities() throws {
        let date = AnalyticsBlackBox.reference.adding(days: 2)
        let workouts = [
            try AnalyticsBlackBox.workout(id: 1, on: date, load: 30),
            try AnalyticsBlackBox.workout(id: 2, on: date, load: 45.5, typeKey: "cycling"),
            try AnalyticsBlackBox.workout(id: 3, on: date, load: nil, typeKey: "strength_training"),
            try AnalyticsBlackBox.workout(id: 4, on: date.adding(days: 1), load: 12),
        ]
        let days = TrainingLoad.days(
            workouts, from: AnalyticsBlackBox.reference,
            through: AnalyticsBlackBox.reference.adding(days: 5))
        #expect(days.map(\.load) == [0, 0, 75.5, 12, 0, 0])
    }

    @Test("Activities after the last day are left out")
    func laterActivitiesIgnored() throws {
        let first = AnalyticsBlackBox.reference
        let last = first.adding(days: 20)
        let inside = try AnalyticsBlackBox.workouts([50, 0, 80, 120, 0, 60], from: first)
        let later = try AnalyticsBlackBox.workout(id: 99, on: last.adding(days: 1), load: 500)
        let without = TrainingLoad.days(inside, from: first, through: last)
        let with = TrainingLoad.days(inside + [later], from: first, through: last)
        #expect(with == without)
    }

    @Test("Fitness starts from zero on the first day: earlier activities do not count")
    func earlierActivitiesIgnored() throws {
        let first = AnalyticsBlackBox.reference
        let last = first.adding(days: 20)
        let inside = try AnalyticsBlackBox.workouts([50, 0, 80], from: first)
        let earlier = try AnalyticsBlackBox.workout(id: 99, on: first.adding(days: -3), load: 500)
        let with = TrainingLoad.days(inside + [earlier], from: first, through: last)
        let without = TrainingLoad.days(inside, from: first, through: last)
        #expect(with == without)
    }

    @Test(
        "A constant load converges to that load from below",
        arguments: [(42.0, 7.0), (28.0, 5.0), (60.0, 10.0)])
    func constantLoadConverges(fitnessDays: Double, fatigueDays: Double) throws {
        let load = 80.0
        let days = try series(
            Array(repeating: load, count: 1500), fitnessDays: fitnessDays,
            fatigueDays: fatigueDays)
        let last = try #require(days.last)
        #expect(AnalyticsBlackBox.isClose(last.fitness, load, tolerance: 1e-6))
        #expect(AnalyticsBlackBox.isClose(last.fatigue, load, tolerance: 1e-6))
        for (previous, day) in zip(days, days.dropFirst()) {
            #expect(day.fitness >= previous.fitness)
            #expect(day.fatigue >= previous.fatigue)
            #expect(day.fitness <= load + 1e-9)
            #expect(day.fatigue <= load + 1e-9)
            // The short average catches up first, so form stays negative while building.
            #expect(day.fatigue >= day.fitness - 1e-9)
        }
    }

    @Test(
        "A single load decays geometrically, at the rate of its window",
        arguments: [(42.0, 7.0), (21.0, 4.0), (90.0, 14.0)])
    func impulseDecaysGeometrically(fitnessDays: Double, fatigueDays: Double) throws {
        let impulse = 300.0
        let days = try series(
            [impulse] + Array(repeating: 0, count: 120), fitnessDays: fitnessDays,
            fatigueDays: fatigueDays)
        let fitnessRatio = days[1].fitness / days[0].fitness
        let fatigueRatio = days[1].fatigue / days[0].fatigue
        #expect(days[0].fitness > 0)
        #expect(days[0].fatigue > days[0].fitness)
        #expect(fatigueRatio < fitnessRatio)
        for (previous, day) in zip(days.dropFirst(), days.dropFirst(2)) {
            #expect(
                AnalyticsBlackBox.isClose(
                    day.fitness / previous.fitness, fitnessRatio, tolerance: 1e-9))
            #expect(
                AnalyticsBlackBox.isClose(
                    day.fatigue / previous.fatigue, fatigueRatio, tolerance: 1e-9))
        }
        // An average: the weights add up to one, so the first day gets 1 - ratio of the load.
        #expect(
            AnalyticsBlackBox.isClose(
                days[0].fitness, impulse * (1 - fitnessRatio), tolerance: 1e-9))
        #expect(
            AnalyticsBlackBox.isClose(
                days[0].fatigue, impulse * (1 - fatigueRatio), tolerance: 1e-9))
        // Over one window the load decays to about 1/e (TrainingPeaks and intervals.icu).
        #expect((0.25...0.40).contains(pow(fitnessRatio, fitnessDays)))
        #expect((0.25...0.40).contains(pow(fatigueRatio, fatigueDays)))
    }

    @Test("Scaling every load scales fitness and fatigue but not form share or zone")
    func scaleInvariance() throws {
        let loads = randomLoads(seed: 7, count: 200)
        let base = try series(loads)
        for factor in [0.5, 2.5, 10.0] {
            let scaled = try series(loads.map { $0 * factor })
            for (day, other) in zip(base, scaled) {
                #expect(
                    AnalyticsBlackBox.isClose(other.fitness, day.fitness * factor, tolerance: 1e-9))
                #expect(
                    AnalyticsBlackBox.isClose(other.fatigue, day.fatigue * factor, tolerance: 1e-9))
                #expect(AnalyticsBlackBox.isClose(other.form, day.form * factor, tolerance: 1e-7))
                if let share = day.formShare, let otherShare = other.formShare {
                    #expect(AnalyticsBlackBox.isClose(share, otherShare, tolerance: 1e-7))
                } else {
                    #expect(day.formShare == nil && other.formShare == nil)
                }
            }
        }
    }

    @Test("Zones do not change when every load is scaled")
    func zonesScaleInvariant() throws {
        let loads = randomLoads(seed: 11, count: 150)
        let base = try series(loads)
        let scaled = try series(loads.map { $0 * 3 })
        // Away from the zone boundaries rounding cannot flip a zone.
        let boundaries = FormZone.allCases.flatMap { [$0.band.lowerBound, $0.band.upperBound] }
        for (day, other) in zip(base, scaled) {
            guard let share = day.formShare,
                boundaries.allSatisfy({ abs($0 - share) > 1e-6 })
            else { continue }
            #expect(day.zone == other.zone)
        }
    }

    @Test("Loads on different days add up: fitness and fatigue are linear")
    func superposition() throws {
        let loads = randomLoads(seed: 3, count: 180)
        let even = loads.enumerated().map { $0.offset.isMultiple(of: 2) ? $0.element : 0 }
        let odd = loads.enumerated().map { $0.offset.isMultiple(of: 2) ? 0 : $0.element }
        let all = try series(loads)
        let evenDays = try series(even)
        let oddDays = try series(odd)
        for index in all.indices {
            let fitness = evenDays[index].fitness + oddDays[index].fitness
            let fatigue = evenDays[index].fatigue + oddDays[index].fatigue
            #expect(AnalyticsBlackBox.isClose(all[index].fitness, fitness, tolerance: 1e-9))
            #expect(AnalyticsBlackBox.isClose(all[index].fatigue, fatigue, tolerance: 1e-9))
        }
    }

    @Test("Shifting activities and range together shifts the result")
    func timeShiftInvariance() throws {
        let loads = randomLoads(seed: 19, count: 120)
        let first = GarminDate.day("2023-12-20")
        let shift = 437
        let workouts = try AnalyticsBlackBox.workouts(loads, from: first)
        let moved = try AnalyticsBlackBox.workouts(loads, from: first.adding(days: shift))
        let days = TrainingLoad.days(
            workouts, from: first, through: first.adding(days: loads.count - 1))
        let shifted = TrainingLoad.days(
            moved, from: first.adding(days: shift),
            through: first.adding(days: shift + loads.count - 1))
        #expect(days.count == shifted.count)
        for (day, other) in zip(days, shifted) {
            #expect(other.date == day.date.adding(days: shift))
            #expect(AnalyticsBlackBox.isClose(other.fitness, day.fitness))
            #expect(AnalyticsBlackBox.isClose(other.fatigue, day.fatigue))
        }
    }

    @Test("More load on one day raises later fitness and fatigue, never earlier ones")
    func causalAndMonotone() throws {
        let loads = randomLoads(seed: 5, count: 90)
        let bumped = loads.enumerated().map { $0.offset == 40 ? $0.element + 100 : $0.element }
        let base = try series(loads)
        let more = try series(bumped)
        for index in base.indices {
            if index < 40 {
                #expect(more[index] == base[index])
            } else {
                #expect(more[index].fitness > base[index].fitness)
                #expect(more[index].fatigue > base[index].fatigue)
            }
        }
    }

    @Test("Longer windows respond more slowly")
    func longerWindowsAreSlower() throws {
        let loads = Array(repeating: 100.0, count: 20)
        let windows = [5.0, 14.0, 42.0, 90.0]
        let fitness = try windows.map { try series(loads, fitnessDays: $0).last?.fitness ?? 0 }
        let fatigue = try windows.map { try series(loads, fatigueDays: $0).last?.fatigue ?? 0 }
        #expect(fitness == fitness.sorted(by: >))
        #expect(fatigue == fatigue.sorted(by: >))
        #expect(Set(fitness).count == windows.count)
    }

    @Test("The default windows are the documented ones")
    func defaultWindows() throws {
        let loads = randomLoads(seed: 23, count: 100)
        let workouts = try AnalyticsBlackBox.workouts(loads, from: AnalyticsBlackBox.reference)
        let last = AnalyticsBlackBox.reference.adding(days: loads.count - 1)
        let implicit = TrainingLoad.days(workouts, from: AnalyticsBlackBox.reference, through: last)
        let explicit = TrainingLoad.days(
            workouts, from: AnalyticsBlackBox.reference, through: last, fitnessDays: 42,
            fatigueDays: 7)
        #expect(implicit == explicit)
    }

    @Test("Form is fitness minus fatigue, and its share is relative to fitness")
    func formAndShare() throws {
        for seed in UInt64(1)...6 {
            for day in try series(randomLoads(seed: seed, count: 120)) {
                #expect(AnalyticsBlackBox.isClose(day.form, day.fitness - day.fatigue))
                #expect(day.fitness >= 0)
                #expect(day.fatigue >= 0)
                if day.fitness > 0 {
                    let share = try #require(day.formShare)
                    #expect(
                        AnalyticsBlackBox.isClose(share, day.form / day.fitness, tolerance: 1e-9))
                    #expect(day.zone == FormZone(share: share))
                }
            }
        }
    }

    @Test("Form is negative while training builds fitness and positive after rest")
    func buildThenRest() throws {
        let loads = Array(repeating: 100.0, count: 60) + Array(repeating: 0, count: 21)
        let days = try series(loads)
        for day in days[3..<60] {
            #expect(day.form < 0)
        }
        for day in days[70...] {
            #expect(day.form > 0)
        }
    }
}

@Suite("Training load: one day's form")
struct BlackBoxTrainingLoadDayTests {
    @Test(
        "Form share and zone of a day",
        arguments: [
            (100.0, 70.0, 0.30, FormZone.detraining),
            (100.0, 85.0, 0.15, FormZone.fresh),
            (100.0, 100.0, 0.0, FormZone.neutral),
            (100.0, 120.0, -0.20, FormZone.productive),
            (100.0, 145.0, -0.45, FormZone.overreaching),
            (50.0, 60.0, -0.20, FormZone.productive),
        ])
    func shareAndZone(fitness: Double, fatigue: Double, share: Double, zone: FormZone) throws {
        let day = TrainingLoad.Day(
            date: AnalyticsBlackBox.reference, load: 0, fitness: fitness, fatigue: fatigue)
        #expect(AnalyticsBlackBox.isClose(day.form, fitness - fatigue))
        let formShare = try #require(day.formShare)
        #expect(AnalyticsBlackBox.isClose(formShare, share, tolerance: 1e-12))
        #expect(day.zone == zone)
        #expect(day.id == AnalyticsBlackBox.reference)
    }

    @Test("Without fitness there is no share and no zone, whatever the fatigue")
    func zeroFitness() {
        for fatigue in [0.0, 5.0, 300.0] {
            let day = TrainingLoad.Day(
                date: AnalyticsBlackBox.reference, load: 10, fitness: 0, fatigue: fatigue)
            #expect(day.formShare == nil)
            #expect(day.zone == nil)
            #expect(day.form == -fatigue)
        }
    }
}

/// Documented behavior that the black-box tests found missing, kept so that it stays fixed.
@Suite("Training load: regressions")
struct TrainingLoadBlackBoxRegressions {
    /// `days(_:from:through:)`: "One `Day` for each day from `first` through `last`".
    @Test("A range ending before it starts has no days")
    func reversedRange() {
        let days = TrainingLoad.days(
            [], from: AnalyticsBlackBox.reference,
            through: AnalyticsBlackBox.reference.adding(days: -1))
        #expect(days.isEmpty)
    }
}
