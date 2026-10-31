import GCPAPISync
import SwiftUI

/// The settings tab: the account, and everything about how the app shows data.
struct SettingsView: View {
    let lastUpdated: Date?
    let export: DataExport
    @Environment(Session.self) private var session
    @Bindable private var preferences = Preferences.shared
    @State private var confirmsDisconnect = false

    private static let sourceCode = URL(
        string: "https://github.com/thomascamminady/gcpapi-sync-ios")

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                regionSection
                displaySection
                summarySection
                activitySection
                AnalysisSection(analysis: $preferences.settings.analysis)
                Section {
                    NavigationLink("Export and Calendar") {
                        ExportView(export: export)
                    }
                    if !session.isDemo {
                        NavigationLink("Sync Between Devices") {
                            SyncSettingsView()
                        }
                    }
                } header: {
                    Text("Your Data")
                } footer: {
                    Text("Your data stays on your device and with Garmin. Nothing is collected.")
                }
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    private var accountSection: some View {
        Section("Garmin") {
            LabeledContent("Account") {
                Text(session.isDemo ? "Sample data" : "Connected")
            }
            if let lastUpdated {
                LabeledContent("Updated") {
                    Text(lastUpdated, format: .relative(presentation: .named))
                }
            }
            Toggle("Refresh in the Background", isOn: $preferences.settings.refreshesInBackground)
            Button(session.isDemo ? "Leave Sample Data" : "Disconnect", role: .destructive) {
                confirmsDisconnect = true
            }
            .confirmationDialog(
                "Disconnect from Garmin?", isPresented: $confirmsDisconnect,
                titleVisibility: .visible
            ) {
                Button("Disconnect", role: .destructive) {
                    session.signOut()
                }
            } message: {
                Text(
                    "Your API key is removed from this device. Your data on Garmin is not affected."
                )
            }
        }
    }

    private var regionSection: some View {
        Section {
            LanguageRow()
            Picker("Units", selection: $preferences.settings.units) {
                Text("Automatic").tag(Settings.Units.automatic)
                Text("Metric").tag(Settings.Units.metric)
                Text("Imperial").tag(Settings.Units.imperial)
            }
            Picker("Week Starts On", selection: $preferences.settings.weekStart) {
                Text("Automatic").tag(Settings.WeekStart.automatic)
                Text("Monday").tag(Settings.WeekStart.monday)
                Text("Sunday").tag(Settings.WeekStart.sunday)
            }
        } header: {
            Text("Language and Region")
        } footer: {
            Text(LanguageRow.footer)
        }
    }

    private var displaySection: some View {
        Section {
            Toggle("Dense Mode", isOn: denseMode)
            NavigationLink("Colors") {
                ColorSettingsView()
            }
        } header: {
            Text("Display")
        } footer: {
            Text(
                """
                Dense mode fits more on the screen: smaller charts, three tiles a row, compact \
                lists.
                """
            )
        }
    }

    private var denseMode: Binding<Bool> {
        Binding {
            preferences.settings.density == .dense
        } set: {
            preferences.settings.density = $0 ? .dense : .comfortable
        }
    }

    private var summarySection: some View {
        Section("Summary") {
            NavigationLink("Tiles") {
                List {
                    ForEach(Metric.allCases) { metric in
                        Toggle(isOn: shown(metric.rawValue, in: \.hiddenTiles)) {
                            Label(metric.title, systemImage: metric.symbol)
                        }
                    }
                }
                .navigationTitle("Tiles")
            }
            Toggle("Trends", isOn: $preferences.settings.showsTrends)
            Picker("Detail Screens Show", selection: $preferences.settings.detailDays) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.caption).tag(range.days)
                }
            }
        }
    }

    private var activitySection: some View {
        Section("Activities") {
            Picker("Route Colors", selection: $preferences.settings.routeColoring) {
                Text("Heart Rate Zone").tag(Settings.RouteColoring.heartRateZone)
                Text("Heart Rate").tag(Settings.RouteColoring.heartRate)
                Text("Sport").tag(Settings.RouteColoring.sport)
            }
            Picker("Map", selection: $preferences.settings.mapStyle) {
                Text("Standard").tag(Settings.MapStyle.standard)
                Text("Hybrid").tag(Settings.MapStyle.hybrid)
                Text("Satellite").tag(Settings.MapStyle.satellite)
            }
            NavigationLink("Charts") {
                List {
                    ForEach(TrackMeasure.allCases) { measure in
                        Toggle(
                            measure.title(for: .running),
                            isOn: shown(measure.rawValue, in: \.hiddenCharts))
                    }
                }
                .navigationTitle("Charts")
            }
        }
    }

    /// Whether `key` is not in the hidden set at `path`.
    private func shown(
        _ key: String, in path: WritableKeyPath<Settings, Set<String>>
    )
        -> Binding<Bool>
    {
        Binding {
            !preferences.settings[keyPath: path].contains(key)
        } set: { isShown in
            if isShown {
                preferences.settings[keyPath: path].remove(key)
            } else {
                preferences.settings[keyPath: path].insert(key)
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            LabeledContent("GCPAPISync", value: packageVersion)
            if let url = Self.sourceCode {
                Link("Source Code", destination: url)
            }
            NavigationLink("Licenses") {
                LicensesView()
            }
        } header: {
            Text("About")
        } footer: {
            Text(
                """
                A personal, open-source project. Not affiliated with or endorsed by Garmin or \
                Wahoo Fitness. Garmin and Garmin Connect are trademarks of Garmin Ltd.
                """
            )
        }
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

/// The parameters of the training analyses.
private struct AnalysisSection: View {
    @Binding var analysis: AnalysisSettings

    /// `Top 20%`.
    private var hardDays: String {
        let share = analysis.hardShare.formatted(.percent.precision(.fractionLength(0)))
        return String(localized: "Top \(share)")
    }

    var body: some View {
        Section {
            Stepper(value: $analysis.fitnessDays, in: 21...84, step: 7) {
                LabeledContent("Fitness", value: Format.days(Int(analysis.fitnessDays)))
            }
            Stepper(value: $analysis.fatigueDays, in: 3...14, step: 1) {
                LabeledContent("Fatigue", value: Format.days(Int(analysis.fatigueDays)))
            }
            Stepper(value: $analysis.hardShare, in: 0.1...0.4, step: 0.05) {
                LabeledContent("Hard Days", value: hardDays)
            }
            Stepper(value: $analysis.baselineDays, in: 14...56, step: 7) {
                LabeledContent("Usual Level", value: Format.days(analysis.baselineDays))
            }
            if analysis != AnalysisSettings() {
                Button("Restore Defaults") {
                    analysis = AnalysisSettings()
                }
            }
        } header: {
            Text("Analysis")
        } footer: {
            Text(
                """
                Fitness and fatigue average your training load over these days. Recovery \
                Response counts the top share of your training days by load as hard, and \
                compares the days around them with the median of the days before.
                """
            )
        }
    }
}

/// Every color the app draws with, by group, each with its own color picker.
struct ColorSettingsView: View {
    @Bindable private var preferences = Preferences.shared

    var body: some View {
        List {
            themeSection
            colormapSection
            ForEach(ColorRole.Group.allCases) { group in
                Section(group.title) {
                    ForEach(group.roles) { role in
                        ColorPicker(selection: binding(role), supportsOpacity: false) {
                            HStack {
                                Text(role.title)
                                if preferences.isCustom(role) {
                                    Spacer()
                                    Button("Reset", systemImage: "arrow.uturn.backward") {
                                        preferences.setColor(nil, for: role)
                                    }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Colors")
        .toolbar {
            if !preferences.settings.colors.isEmpty {
                Button("Reset All") {
                    preferences.settings.colors = [:]
                }
            }
        }
    }

    private var themeSection: some View {
        Section {
            Picker("Theme", selection: $preferences.settings.theme) {
                ForEach(ColorTheme.allCases, id: \.self) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            ThemePreview()
        } footer: {
            Text(
                """
                Okabe–Ito and Balanced can be told apart with every common color-vision \
                deficiency. Colors changed below stay as they are when the theme changes.
                """)
        }
    }

    /// The color map for coloring by value, each shown as its gradient.
    private var colormapSection: some View {
        Section {
            Picker("Color Map", selection: $preferences.settings.colormap) {
                ForEach(Colormap.allCases) { map in
                    HStack {
                        Text(map.title)
                        Spacer()
                        Capsule()
                            .fill(map.gradient(isReversed: preferences.settings.reversesColormap))
                            .frame(width: 120, height: 10)
                            .accessibilityHidden(true)
                    }
                    .tag(map)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Toggle("Reverse", isOn: $preferences.settings.reversesColormap)
        } header: {
            Text("Coloring by Value")
        } footer: {
            Text(
                """
                For the dashboard's months and routes by heart rate. These maps are perceptually \
                uniform: equal steps of value look like equal steps of color, and they read in \
                grayscale and with color-vision deficiencies. Cividis is made for them.
                """)
        }
    }

    private func binding(_ role: ColorRole) -> Binding<Color> {
        Binding {
            preferences.color(role)
        } set: {
            preferences.setColor($0, for: role)
        }
    }
}

/// The theme's main hues side by side.
private struct ThemePreview: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Metric.allCases) { metric in
                Circle()
                    .fill(metric.tint)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel(metric.title)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SettingsView(
        lastUpdated: .now,
        export: DataExport(
            fetchHealth: { end, days in .sample(endingOn: end, days: days) },
            fetchActivities: { _, _ in [] })
    )
    .environment(Session.preview)
}

/// The app's language, which the system keeps per app: in the Settings app on iPhone and iPad,
/// in System Settings on the Mac.
private struct LanguageRow: View {
    @Environment(\.openURL) private var openURL

    static var footer: String {
        ProcessInfo.processInfo.isMacCatalystApp
            ? String(
                localized: """
                    Choose the language in System Settings › General › Language & Region › \
                    Applications.
                    """)
            : String(
                localized:
                    "Language opens the Settings app, where you choose it for this app alone.")
    }

    /// The language the app shows, in that language: `English`, `Deutsch`.
    static var current: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
    }

    var body: some View {
        if ProcessInfo.processInfo.isMacCatalystApp {
            LabeledContent("Language", value: Self.current)
        } else {
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                LabeledContent("Language") {
                    HStack(spacing: 6) {
                        Text(Self.current)
                        Image(systemName: "arrow.up.forward.app")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                }
            }
            .foregroundStyle(.primary)
            .accessibilityHint("Opens the Settings app")
        }
    }
}
