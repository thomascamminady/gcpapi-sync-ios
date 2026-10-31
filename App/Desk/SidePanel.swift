import GCPAPISync
import SwiftUI

/// The dashboard's column of figures: this month's sports, the state of training, race
/// predictions, the latest health values and training paces.
struct SidePanel: View {
    let data: TrainingData
    let health: HealthHistory?
    /// Whether the sections sit side by side, below the tables, instead of one above the other.
    var isGrid = false

    private var today: GarminDate {
        data.loadHistory.last?.date ?? GarminDate.today()
    }

    private var vo2max: Double? {
        health?.latest(\.vo2max)
    }

    var body: some View {
        if isGrid {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300), spacing: 32, alignment: .top)],
                alignment: .leading, spacing: 20
            ) {
                sections
            }
        } else {
            VStack(alignment: .leading, spacing: 24) {
                sections
            }
        }
    }

    @ViewBuilder private var sections: some View {
        sports
        TrainingFigures(loads: data.loadHistory, vo2max: vo2max)
        if let vo2max {
            predictions(vo2max)
        }
        if let health {
            HealthFigures(history: health)
        }
        if let vo2max {
            paces(vo2max)
        }
    }

    private var sports: some View {
        let first = CalendarMonth.first(of: today)
        let month = data.history.filter { $0.date >= first && $0.date <= today }
        return PanelSection(title: "This Month") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], spacing: 8) {
                ForEach(ActivityTotals.bySport(month), id: \.sport) { item in
                    NavigationLink(value: DeskRoute.month(first, item.sport)) {
                        SportTotal(sport: item.sport, totals: item.totals)
                    }
                    .buttonStyle(.plain)
                }
            }
            if month.isEmpty {
                Text("No activities.")
                    .font(DeskStyle.font)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func predictions(_ vo2max: Double) -> some View {
        PanelSection(title: "Race Predictions") {
            ForEach(Performance.predictions(vo2max: vo2max), id: \.metres) { prediction in
                PanelRow(
                    label: Self.raceName(prediction.metres),
                    value: Format.clock(seconds: prediction.seconds),
                    detail: Format.pace(
                        metresPerSecond: prediction.metresPerSecond, sport: .running)
                )
                .linked(to: Route.metric(.vo2max))
            }
            Text("From the VO2max estimated from your runs, by Daniels' formulas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func paces(_ vo2max: Double) -> some View {
        PanelSection(title: "Training Paces") {
            ForEach(Performance.Intensity.allCases) { intensity in
                if let speeds = Performance.speeds(intensity, vo2max: vo2max) {
                    PanelRow(
                        label: intensity.title,
                        value: Self.paceRange(speeds),
                        detail: Self.shareRange(intensity.shares)
                    )
                    .linked(to: Route.metric(.vo2max))
                }
            }
        }
    }

    /// `5 km`, `Half Marathon`.
    static func raceName(_ metres: Double) -> String {
        switch metres {
        case 21_097.5: String(localized: "Half Marathon")
        case 42_195: String(localized: "Marathon")
        default:
            Measurement(value: metres / 1000, unit: UnitLength.kilometers).formatted(
                .measurement(width: .abbreviated, usage: .asProvided))
        }
    }

    /// `4:39–5:50 /km`: from the fastest pace to the slowest.
    static func paceRange(_ speeds: ClosedRange<Double>) -> String {
        let unit = Format.usesMiles ? 1609.344 : 1000
        let fast = Format.clock(seconds: unit / speeds.upperBound)
        let slow = Format.clock(seconds: unit / speeds.lowerBound)
        return "\(fast)–\(slow) \(Format.usesMiles ? "/mi" : "/km")"
    }

    /// `59–74 %`.
    static func shareRange(_ shares: ClosedRange<Double>) -> String {
        let low = Int((shares.lowerBound * 100).rounded())
        return "\(low)–\(shares.upperBound.formatted(.percent.precision(.fractionLength(0))))"
    }
}

/// One sport's total of the month: its distance, or its time when it has none.
private struct SportTotal: View {
    let sport: Sport
    let totals: ActivityTotals

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sport.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    totals.distance > 0
                        ? Format.distance(metres: totals.distance)
                        : Format.hours(seconds: totals.duration)
                )
                .font(DeskStyle.font.weight(.semibold))
                .monospacedDigit()
                Text("\(totals.activityCount)×")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: sport.symbol)
                .foregroundStyle(sport.color)
                .accessibilityHidden(true)
        }
        .padding(8)
        .surface(cornerRadius: 8)
        .accessibilityElement(children: .combine)
    }
}

/// The state of training: VO2max, fitness, fatigue, form, and how load is spread over the last
/// week.
private struct TrainingFigures: View {
    let loads: [TrainingLoad.Day]
    let vo2max: Double?
    @ScaledMetric(relativeTo: .subheadline) private var barWidth: CGFloat = 90

    var body: some View {
        PanelSection(title: "Training") {
            if let vo2max {
                row(
                    String(localized: "VO2max"),
                    vo2max.formatted(.number.precision(.fractionLength(1))),
                    (vo2max - 30) / 40, ColorRole.metric(.vo2max).color, link: Route.metric(.vo2max)
                )
            }
            if let day = loads.last {
                loadRows(day)
            }
            balanceRows
            Text(
                "Workload ratio: fatigue over fitness. Monotony and strain: the last 7 days."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Fitness and fatigue on one scale, form around zero, and their ratio.
    @ViewBuilder
    private func loadRows(_ day: TrainingLoad.Day) -> some View {
        let scale = loads.map { max($0.fitness, $0.fatigue) }.max() ?? 0
        row(
            String(localized: "Fitness"), Int(day.fitness.rounded()).formatted(),
            scale > 0 ? day.fitness / scale : 0, ColorRole.fitness.color)
        row(
            String(localized: "Fatigue"), Int(day.fatigue.rounded()).formatted(),
            scale > 0 ? day.fatigue / scale : 0, ColorRole.fatigue.color)
        PanelRow(
            label: String(localized: "Form"),
            value: Int(day.form.rounded()).formatted(
                .number.sign(strategy: .always(includingZero: false)))
        ) {
            MeterBar(
                fraction: day.formShare.map { $0 / 0.5 } ?? 0,
                color: day.formShare.map { FormZone(share: $0).color } ?? .secondary,
                isCentered: true
            )
            .frame(width: barWidth)
        }
        .linked(to: DeskRoute.trainingLoad)
        if let ratio = LoadBalance.workloadRatio(day) {
            row(
                String(localized: "Workload Ratio"),
                ratio.formatted(.number.precision(.fractionLength(2))),
                ratio / 2, Self.ratioColor(ratio))
        }
    }

    /// Monotony and strain of the last seven days.
    @ViewBuilder private var balanceRows: some View {
        let week = loads.suffix(7).map(\.load)
        if let monotony = LoadBalance.monotony(week), let strain = LoadBalance.strain(week) {
            row(
                String(localized: "Monotony"),
                monotony.formatted(.number.precision(.fractionLength(2))), monotony / 3,
                monotony > 2 ? ColorRole.status(.poor).color : ColorRole.status(.good).color)
            row(
                String(localized: "Strain"), Int(strain.rounded()).formatted(),
                strain / max(Self.largestStrain(loads), 1), ColorRole.fatigue.color)
        }
    }

    /// A figure with its bar, opening `link`: the training load unless said otherwise.
    private func row(
        _ label: String, _ value: String, _ fraction: Double, _ color: Color,
        link: some Hashable = DeskRoute.trainingLoad
    ) -> some View {
        PanelRow(label: label, value: value) {
            MeterBar(fraction: fraction, color: color)
                .frame(width: barWidth)
        }
        .linked(to: link)
    }

    /// About 0.8 to 1.3 is training as usual; above 1.5, far more than usual.
    static func ratioColor(_ ratio: Double) -> Color {
        switch ratio {
        case ..<0.8: ColorRole.fitness.color
        case 0.8..<1.3: ColorRole.status(.good).color
        case 1.3..<1.5: ColorRole.status(.fair).color
        default: ColorRole.status(.poor).color
        }
    }

    /// The highest strain of any 7 days in `loads`, which the bar is relative to.
    static func largestStrain(_ loads: [TrainingLoad.Day]) -> Double {
        guard loads.count >= 7 else { return 0 }
        return (7...loads.count).compactMap { end in
            LoadBalance.strain(loads[(end - 7)..<end].map(\.load))
        }.max() ?? 0
    }
}

/// The latest value of every health metric, each opening its detail screen, and the trends.
private struct HealthFigures: View {
    let history: HealthHistory

    var body: some View {
        PanelSection(title: "Health") {
            VStack(spacing: 0) {
                ForEach(Metric.allCases) { metric in
                    NavigationLink(value: Route.metric(metric)) {
                        row(metric)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink(value: Route.overview) {
                    HStack(spacing: 8) {
                        Label("Trends", systemImage: "chart.xyaxis.line")
                            .foregroundStyle(ColorRole.accent.color)
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(DeskStyle.font)
                    .padding(.vertical, 5)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ metric: Metric) -> some View {
        let tile = metric.tile(of: history)
        return HStack(spacing: 8) {
            Image(systemName: metric.symbol)
                .foregroundStyle(ColorRole.metric(metric).color)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(metric.shortTitle)
                .lineLimit(1)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile?.value ?? "–")
                    .fontWeight(.medium)
                if let unit = tile?.unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .monospacedDigit()
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .font(DeskStyle.font)
        .padding(.vertical, 5)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(tile?.detail ?? "")
    }
}
