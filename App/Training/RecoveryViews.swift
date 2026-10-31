import Charts
import GCPAPISync
import SwiftUI
import UIKit

/// The training tab's recovery card: the clearest response to hard training.
struct RecoveryCard: View {
    let phase: TrainingModel.RecoveryPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(
                title: "Recovery Response", symbol: "arrow.uturn.backward.circle.fill",
                tint: OverviewMetric.hrv.color, opensDetail: isNavigable)
            content
        }
        .allowsHitTesting(false)
        .cardStyle()
        .contentShape(.rect(cornerRadius: 26))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isNavigable ? Text("Shows details") : Text(verbatim: ""))
    }

    private var isNavigable: Bool {
        if case .loaded(let response) = phase { response.isSufficient } else { false }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Comparing your hard training days with the days after them…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let problem):
            Label(problem.message, systemImage: problem.symbol)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .loaded(let response):
            if response.isSufficient,
                let curve = response.headline ?? response.curves.first(where: { $0.peak != nil })
            {
                Text(curve.sentence)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                RecoveryChart(curve: curve)
                    .chartHeight(150)
                RecoveryLegend(metric: curve.metric)
                Text(RecoveryDetailView.basis(of: response))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    """
                    Needs at least \(RecoveryResponse.minimumEvents) hard training days, \
                    counting days in a row once, with health data from the weeks before them; \
                    \(response.hardEvents) so far.
                    """
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// A metric's average change around hard days and rest days, with 95% confidence bands.
struct RecoveryChart: View {
    let curve: RecoveryResponse.Curve

    private static let restColor = Color.gray

    var body: some View {
        Chart {
            RuleMark(y: .value("Usual", 0))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
            series(curve.rest, name: "rest", color: Self.restColor, dashed: true)
            series(curve.hard, name: "hard", color: curve.metric.color, dashed: false)
        }
        .chartXScale(domain: -1.3...3.3)
        .chartXAxis {
            AxisMarks(values: RecoveryResponse.lags) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let lag = value.as(Int.self) {
                        Text(Self.label(lag: lag))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(percent.formatted(.number.precision(.fractionLength(0))))%")
                    }
                }
            }
        }
    }

    @ChartContentBuilder
    private func series(
        _ points: [RecoveryResponse.Point], name: String, color: Color, dashed: Bool
    ) -> some ChartContent {
        ForEach(points.filter { $0.events > 0 }, id: \.lag) { point in
            AreaMark(
                x: .value("Day", point.lag),
                yStart: .value("Low", point.mean - point.margin),
                yEnd: .value("High", point.mean + point.margin),
                series: .value("Band", "\(name) band")
            )
            .foregroundStyle(color.opacity(dashed ? 0.1 : 0.18))
            .interpolationMethod(.linear)
            LineMark(
                x: .value("Day", point.lag), y: .value("Change", point.mean),
                series: .value("Days", name)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: dashed ? [4, 4] : []))
            .interpolationMethod(.linear)
            PointMark(x: .value("Day", point.lag), y: .value("Change", point.mean))
                .foregroundStyle(color)
                .symbolSize(dashed ? 30 : 60)
        }
    }

    /// `Before`, `Day`, `+1` …
    static func label(lag: Int) -> String {
        switch lag {
        case ..<0: String(localized: "Before")
        case 0: String(localized: "Day")
        default: "+\(lag)"
        }
    }
}

/// What the two lines of a recovery chart are.
struct RecoveryLegend: View {
    let metric: OverviewMetric

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Capsule().fill(metric.color).frame(width: 16, height: 3)
                Text("After hard days")
            }
            HStack(spacing: 6) {
                Capsule()
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 16, height: 1)
                Text("After rest days")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// Every metric's response to hard training, and how it is computed.
struct RecoveryDetailView: View {
    let response: RecoveryResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(
                    """
                    How your body responds to your hardest training days: the average change \
                    from your usual level on the days around them, compared with rest days.
                    """
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                Text(Self.basis(of: response))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(response.curves) { curve in
                    VStack(alignment: .leading, spacing: 12) {
                        OverviewLegendLabel(metric: curve.metric)
                            .font(.subheadline.weight(.semibold))
                        Text(curve.sentence)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        RecoveryChart(curve: curve)
                            .chartHeight(170)
                        RecoveryLegend(metric: curve.metric)
                    }
                    .cardStyle()
                    .accessibilityElement(children: .combine)
                }
                method
            }
            .padding()
            .readableWidth()
        }
        .background(Color.page)
        .navigationTitle("Recovery Response")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// `Based on 31 hard days (load 140 or more) and 22 rest days.`
    static func basis(of response: RecoveryResponse) -> String {
        let threshold = response.threshold.map { Int($0.rounded()) } ?? 0
        let days = TrainingLoader.shownDays + TrainingLoader.warmUpDays
        let sentence = AttributedString(
            localized: """
                Based on ^[\(response.hardDays) hard day](inflect: true) (training load \
                \(threshold) or more) and ^[\(response.restDays) rest day](inflect: true) in the \
                last \(days) days.
                """)
        return String(sentence.characters)
    }

    /// How the response is computed, with the user's parameters.
    static func method(of response: RecoveryResponse) -> String {
        let share = response.hardShare.formatted(.percent.precision(.fractionLength(0)))
        return String(
            localized: """
                A day is hard when its training load is in the top \(share) of your training \
                days; hard days in a row count once, from the first. Around each, every value \
                is compared with your usual level: the median of the \(response.baselineDays) \
                days before it. Averaging over all hard \
                days cancels out what happens by chance and leaves your typical response; the \
                band is its 95% confidence interval, and a change counts as clear only when the \
                band excludes zero. Rest days, averaged the same way, show what happens without \
                training.

                HRV and sleep belong to the night ending on a day, so they show a hard day's \
                effect from the day after. This shows what tends to follow hard training, not \
                what causes it: travel, illness or stress around hard days count too.
                """)
    }

    private var method: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("How It Works", systemImage: "info.circle")
                .font(.headline)
            Text(Self.method(of: response))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}
