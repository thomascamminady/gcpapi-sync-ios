import GCPAPISync
import SwiftUI
import UIKit

/// The week at a glance: one card per metric.
struct DashboardView: View {
    let week: HealthWeek
    var refreshProblem: Problem?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let refreshProblem {
                    ProblemBanner(problem: refreshProblem)
                }
                stepsCard
                sleepCard
                heartRateCard
                hrvCard
                bodyBatteryCard
                stressCard
                intensityCard
                Text("Data from Garmin Connect. Not affiliated with Garmin.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical)
            }
            .padding(.horizontal)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var stepsCard: some View {
        MetricCard(
            title: String(localized: "Steps"), symbol: "figure.walk", tint: .teal,
            value: Format.number(week.average(\.steps)), unit: String(localized: "per day"),
            detail: String(
                localized:
                    "Today \(Format.number(week.days.last?.steps)) · \(goalDays) of 7 days at goal")
        ) {
            StepsChart(days: week.days)
        }
    }

    private var goalDays: Int {
        week.days.filter { day in
            guard let steps = day.steps, let goal = day.stepGoal else { return false }
            return steps >= goal
        }.count
    }

    private var sleepCard: some View {
        let average = week.averageSleep
        return MetricCard(
            title: String(localized: "Sleep"), symbol: "bed.double.fill", tint: .indigo,
            value: Format.duration(seconds: average?.total), unit: String(localized: "average"),
            detail: average?.score.map { String(localized: "Average sleep score \($0)") }
                ?? String(localized: "No sleep score")
        ) {
            SleepChart(days: week.days)
        }
    }

    private var heartRateCard: some View {
        MetricCard(
            title: String(localized: "Resting Heart Rate"), symbol: "heart.fill", tint: .red,
            value: Format.number(week.latest(\.restingHeartRate)), unit: "bpm",
            detail: String(
                localized: "7-day average \(Format.number(week.average(\.restingHeartRate))) bpm")
        ) {
            TrendChart(
                days: week.days, metric: \.restingHeartRate,
                label: String(localized: "Resting heart rate"), tint: .red)
        }
    }

    private var hrvCard: some View {
        MetricCard(
            title: String(localized: "Heart Rate Variability"), symbol: "waveform.path.ecg",
            tint: .purple, value: Format.number(week.latest(\.hrv)), unit: "ms",
            detail: String(
                localized: "Last night · 7-day average \(Format.number(week.average(\.hrv))) ms")
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if let status = Format.hrvStatus(week.latest(\.hrvStatus)) {
                    StatusBadge(label: status.label, color: status.color)
                }
                TrendChart(
                    days: week.days, metric: \.hrv, label: String(localized: "HRV"), tint: .purple)
            }
        }
    }

    private var bodyBatteryCard: some View {
        MetricCard(
            title: String(localized: "Body Battery"), symbol: "bolt.heart.fill", tint: .green,
            value: Format.number(week.days.last?.bodyBatteryHigh),
            unit: String(localized: "today's high"),
            detail: String(localized: "Daily range from lowest to highest")
        ) {
            BodyBatteryChart(days: week.days)
        }
    }

    private var stressCard: some View {
        let average = week.average(\.stress)
        return MetricCard(
            title: String(localized: "Stress"), symbol: "brain.head.profile", tint: .orange,
            value: Format.number(average), unit: String(localized: "average"),
            detail: Format.stressLabel(average)
        ) {
            StressChart(days: week.days)
        }
    }

    private var intensityCard: some View {
        let total = week.total(\.intensityMinutes)
        return MetricCard(
            title: String(localized: "Intensity Minutes"), symbol: "flame.fill", tint: .orange,
            value: total.formatted(), unit: String(localized: "of 150"),
            detail: total >= 150
                ? String(localized: "Weekly goal reached")
                : String(localized: "\(150 - total) minutes to the weekly goal")
        ) {
            IntensityChart(days: week.days)
        }
    }
}

/// A notice above the cards when refreshing failed.
struct ProblemBanner: View {
    let problem: Problem

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(problem.title).font(.subheadline.weight(.semibold))
                Text(problem.message).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: problem.symbol).foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 18))
    }
}

#Preview {
    DashboardView(week: .sample(endingOn: .today()))
}
