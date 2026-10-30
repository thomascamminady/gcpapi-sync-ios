import SwiftUI

/// Where people connect their Garmin account with a Personal API key.
struct ConnectView: View {
    @Environment(Session.self) private var session
    @State private var apiKey = ""
    @State private var isConnecting = false
    @State private var problem: Problem?
    @FocusState private var keyFieldIsFocused: Bool

    private static let garminConnect = URL(string: "https://connect.garmin.com/")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    instructions
                    keyEntry
                    actions
                    privacyNote
                }
                .padding(24)
                .readableWidth(560)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(
                        colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: .rect(cornerRadius: 20)
                )
                .accessibilityHidden(true)
            Text("Connect Garmin")
                .font(.largeTitle.bold())
            Text(
                """
                See your sleep, heart rate, HRV, stress and activity in one place, \
                straight from Garmin's official Personal API.
                """
            )
            .foregroundStyle(.secondary)
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Get your API key")
                .font(.headline)
            Step(number: 1, text: "Open Garmin Connect on the web and sign in.")
            Step(number: 2, text: "Go to Settings › Personal API and create a key.")
            Step(number: 3, text: "Copy the key and paste it below.")
            if let url = Self.garminConnect {
                Link(destination: url) {
                    Label("Open Garmin Connect", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.top, 4)
            }
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SecureField("API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .focused($keyFieldIsFocused)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: .capsule)
                PasteButton(payloadType: String.self) { strings in
                    apiKey = strings.first ?? ""
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
            }
            if let problem {
                ProblemBanner(problem: problem)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: connect) {
                ZStack {
                    Text("Connect").opacity(isConnecting ? 0 : 1)
                    if isConnecting {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .disabled(
                apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isConnecting)
            Button("Explore with Sample Data") {
                session.startDemo()
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    private var privacyNote: some View {
        Label {
            Text(
                """
                Your key stays in this iPhone's Keychain and is only ever sent to Garmin. \
                This app is not affiliated with Garmin.
                """
            )
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func connect() {
        guard !isConnecting else { return }
        keyFieldIsFocused = false
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await session.connect(apiKey: apiKey)
            } catch {
                withAnimation(.snappy) { problem = Problem(error) }
            }
        }
    }
}

/// One numbered instruction.
private struct Step: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(number, format: .number)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.tint, in: .circle)
            Text(text)
        }
    }
}

#Preview {
    ConnectView()
        .environment(Session.preview)
}
