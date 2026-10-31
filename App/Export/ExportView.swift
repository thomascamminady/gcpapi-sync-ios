import GCPAPISync
import SwiftUI
import UniformTypeIdentifiers

/// Exporting data: files to share or save, a folder kept up to date, and the calendar.
struct ExportView: View {
    let export: DataExport
    @Bindable private var preferences = Preferences.shared
    @State private var period = RangeChoice.last(90)
    @State private var contents: Set<DataExport.Content> = [.daily, .activities]
    @State private var choosesFolder = false
    @State private var folder = FolderSync().folder
    @State private var calendarProblem: Problem?

    var body: some View {
        Form {
            filesSection
            folderSection
            calendarSection
        }
        .navigationTitle("Export")
        .onChange(of: period) { export.reset() }
        .onChange(of: contents) { export.reset() }
        .fileImporter(isPresented: $choosesFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result, (try? FolderSync().choose(url)) != nil {
                folder = FolderSync().folder
            }
        }
    }

    private var filesSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Period")
                RangePicker(
                    choice: $period,
                    presets: [
                        (7, String(localized: "7D")), (30, String(localized: "30D")),
                        (90, String(localized: "90D")), (365, String(localized: "1Y")),
                    ],
                    bounds: GarminDate.today().adding(days: -3 * 365)...GarminDate.today())
            }
            ForEach(DataExport.Content.allCases) { content in
                Toggle(content.title, isOn: included(content))
            }
            exportAction
        } header: {
            Text("Files")
        } footer: {
            Text(
                """
                Share to Mail or AirDrop, or save to Files: on this device, in iCloud Drive, \
                Dropbox or any other storage you use. Nothing is sent anywhere else.
                """
            )
        }
    }

    /// Preparing the files, then sharing them.
    @ViewBuilder private var exportAction: some View {
        switch export.phase {
        case .idle:
            Button("Prepare Files", systemImage: "doc.badge.arrow.up") {
                Task { await prepare() }
            }
            .disabled(contents.isEmpty)
        case .preparing:
            HStack {
                ProgressView()
                Text("Fetching from Garmin…").foregroundStyle(.secondary)
            }
        case .ready(let files):
            ShareLink(items: files) {
                Label(
                    "Share or Save \(Format.files(files.count))",
                    systemImage: "square.and.arrow.up")
            }
        case .failed(let problem):
            Label(problem.message, systemImage: problem.symbol)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await prepare() }
            }
        }
    }

    /// Fetch the period's data and write the chosen files.
    private func prepare() async {
        let today = GarminDate.today()
        await export.prepare(
            days: period.dayCount(through: today), contents: contents,
            today: period.dates(through: today).upperBound)
    }

    private func included(_ content: DataExport.Content) -> Binding<Bool> {
        Binding {
            contents.contains(content)
        } set: { isIncluded in
            if isIncluded {
                contents.insert(content)
            } else {
                contents.remove(content)
            }
        }
    }

    private var folderSection: some View {
        Section {
            if let folder {
                LabeledContent("Folder", value: folder.lastPathComponent)
                if let lastSync = export.lastSync {
                    LabeledContent("Updated") {
                        Text(lastSync, format: .relative(presentation: .named))
                    }
                }
                Button("Stop Updating", role: .destructive) {
                    FolderSync().forget()
                    self.folder = nil
                }
            } else {
                Button("Choose Folder…", systemImage: "folder.badge.plus") {
                    choosesFolder = true
                }
            }
        } header: {
            Text("Keep a Folder Up to Date")
        } footer: {
            Text(
                """
                After every sync, \(FolderSync.dailyFile) and \(FolderSync.activitiesFile) in \
                the folder are updated. Earlier rows stay, so the files grow into your complete \
                history.
                """
            )
        }
    }

    private var calendarSection: some View {
        Section {
            Toggle("Activities in Calendar", isOn: calendarBinding)
            if let calendarProblem {
                Label(calendarProblem.message, systemImage: calendarProblem.symbol)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text(
                """
                Adds a calendar named Activities to the Calendar app with your activities of \
                the last 365 days, kept up to date. Calendar access is asked for only now and \
                used only for this calendar; it syncs wherever your calendars sync.
                """
            )
        }
    }

    private var calendarBinding: Binding<Bool> {
        Binding {
            preferences.settings.exportsToCalendar
        } set: { isOn in
            Task { await setCalendar(isOn) }
        }
    }

    private func setCalendar(_ isOn: Bool) async {
        let calendar = CalendarSync()
        calendarProblem = nil
        guard isOn else {
            preferences.settings.exportsToCalendar = false
            try? calendar.removeCalendar()
            return
        }
        do {
            guard try await calendar.requestAccess() else {
                calendarProblem = .calendarDenied
                return
            }
            preferences.settings.exportsToCalendar = true
            let workouts = try await export.activities(days: 365)
            try calendar.sync(
                workouts, from: GarminDate.today().adding(days: -364).startOfDay(in: .current))
        } catch {
            calendarProblem = Problem(error)
        }
    }
}
