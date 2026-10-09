import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var loginItemService = LoginItemService()
    @State private var notificationStatus = "Not requested"
    @State private var newsAPIKey = ""
    @State private var hasStoredNewsAPIKey = false
    @State private var newsAPIStatus: String?
    @AppStorage("monitoring.apiBaseURL") private var monitoringAPIBaseURL = MonitoringAPIService.defaultBaseURL
    @State private var monitoringAPIToken = ""
    @State private var hasStoredMonitoringAPIToken = false
    @State private var monitoringConnectionState = MonitoringConnectionState.notTested

    private let newsAPIKeyStore = NewsAPIKeyStore()
    private let monitoringCredentialStore = MonitoringAPICredentialStore()
    private let monitoringAPIService = MonitoringAPIService()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch JARVIS when I log in", isOn: Binding(
                    get: { loginItemService.isEnabled },
                    set: { loginItemService.setEnabled($0) }
                ))

                if loginItemService.requiresApproval {
                    HStack {
                        Text("macOS requires approval in Login Items.")
                        Spacer()
                        Button("Open System Settings") { loginItemService.openSystemSettings() }
                    }
                }

                if let errorMessage = loginItemService.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Wake briefing") {
                Toggle("Show a briefing after waking", isOn: $appState.showWakeBriefing)
                Picker("Minimum sleep duration", selection: $appState.minimumSleepForBriefing) {
                    Text("5 minutes").tag(TimeInterval(5 * 60))
                    Text("15 minutes").tag(TimeInterval(15 * 60))
                    Text("30 minutes").tag(TimeInterval(30 * 60))
                    Text("1 hour").tag(TimeInterval(60 * 60))
                }
                .disabled(!appState.showWakeBriefing)

                Button("Preview briefing") { appState.requestBriefing() }
            }

            Section("JARVIS voice") {
                Toggle("Enable text to speech", isOn: $speechService.isEnabled)
                Toggle("Speak wake briefings automatically", isOn: $speechService.speakWakeBriefings)
                    .disabled(!speechService.isEnabled)
                Toggle("Speak new critical intelligence alerts", isOn: $speechService.speakCriticalAlerts)
                    .disabled(!speechService.isEnabled)

                Picker("Voice", selection: $speechService.voiceIdentifier) {
                    Text("British English · macOS default").tag("")
                    ForEach(speechService.availableVoices) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.id)
                    }
                }
                .disabled(!speechService.isEnabled)

                LabeledContent("Speaking rate") {
                    Slider(value: $speechService.rate, in: 0.35...0.62, step: 0.01)
                        .frame(width: 220)
                }
                .disabled(!speechService.isEnabled)

                LabeledContent("Pitch") {
                    Slider(value: $speechService.pitch, in: 0.7...1.3, step: 0.05)
                        .frame(width: 220)
                }
                .disabled(!speechService.isEnabled)

                LabeledContent("Volume") {
                    Slider(value: $speechService.volume, in: 0...1, step: 0.05)
                        .frame(width: 220)
                }
                .disabled(!speechService.isEnabled)

                Toggle("Respect quiet hours", isOn: $speechService.quietHoursEnabled)
                    .disabled(!speechService.isEnabled)
                if speechService.quietHoursEnabled {
                    HStack {
                        Text("Quiet hours")
                        Picker("Start", selection: $speechService.quietStartHour) {
                            ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                        }
                        Picker("End", selection: $speechService.quietEndHour) {
                            ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                        }
                    }
                    .disabled(!speechService.isEnabled)
                }

                HStack {
                    Button("Preview voice") { speechService.preview() }
                        .disabled(!speechService.isEnabled)
                    Button("Stop") { speechService.stop() }
                        .disabled(!speechService.isSpeaking)
                    Spacer()
                    Text("Speech is generated locally by macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Notifications") {
                HStack {
                    Text(notificationStatus)
                    Spacer()
                    Button("Request permission") {
                        Task {
                            do {
                                let granted = try await NotificationService().requestAuthorization()
                                notificationStatus = granted ? "Authorised" : "Not authorised"
                            } catch {
                                notificationStatus = "Request failed"
                            }
                        }
                    }
                }
            }

            Section("News API") {
                SecureField("Paste your NewsAPI.org key", text: $newsAPIKey)
                    .textContentType(.password)

                HStack {
                    Text(hasStoredNewsAPIKey ? "A key is securely stored in macOS Keychain." : "No API key stored. RSS feeds will be used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if hasStoredNewsAPIKey {
                        Button("Remove", role: .destructive) { removeNewsAPIKey() }
                    }
                    Button("Save") { saveNewsAPIKey() }
                        .disabled(newsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let newsAPIStatus {
                    Text(newsAPIStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Monitoring API") {
                TextField("API URL", text: $monitoringAPIBaseURL)
                    .textContentType(.URL)

                SecureField(
                    hasStoredMonitoringAPIToken ? "Paste a replacement token" : "Paste your read token",
                    text: $monitoringAPIToken
                )
                .textContentType(.password)

                HStack(spacing: 8) {
                    Circle()
                        .fill(monitoringConnectionState.colour)
                        .frame(width: 8, height: 8)
                    Text(monitoringConnectionState.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack {
                    Text(hasStoredMonitoringAPIToken ? "Token stored securely in macOS Keychain." : "No monitoring token stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if hasStoredMonitoringAPIToken {
                        Button("Remove Token", role: .destructive) { removeMonitoringAPIToken() }
                    }
                    Button("Save") { saveMonitoringAPISettings() }
                        .disabled(!canSaveMonitoringAPISettings)
                    Button("Test Connection") {
                        Task { await testMonitoringAPIConnection() }
                    }
                    .disabled(!canTestMonitoringAPIConnection || monitoringConnectionState.isTesting)
                }
            }

            Section("Laravel Cloud cost guard") {
                Text("Laravel Cloud does not currently expose a documented live-spend API. Use its native billing alert as the authoritative cost threshold; JARVIS will not estimate or invent charges.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Open Laravel Cloud", destination: URL(string: "https://cloud.laravel.com")!)
            }

            Section("Data, backup and restore") {
                BackupSettingsView()
            }

            Section("Data and privacy") {
                Text("Tasks, projects, locations, and backups are stored locally. NewsAPI.org and monitoring API credentials are stored in macOS Keychain and excluded from backups and exports. Live services receive only the information required for their requests.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 620, minHeight: 600)
        .navigationTitle("Settings")
        .onAppear {
            loginItemService.refresh()
            hasStoredNewsAPIKey = newsAPIKeyStore.read() != nil
            hasStoredMonitoringAPIToken = monitoringCredentialStore.read() != nil
        }
        .task { await refreshNotificationStatus() }
    }

    private func saveNewsAPIKey() {
        do {
            try newsAPIKeyStore.save(newsAPIKey)
            newsAPIKey = ""
            hasStoredNewsAPIKey = true
            newsAPIStatus = "Saved. NewsAPI.org will be used on the next refresh."
        } catch {
            newsAPIStatus = error.localizedDescription
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(
            from: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        )
    }

    private func removeNewsAPIKey() {
        do {
            try newsAPIKeyStore.delete()
            newsAPIKey = ""
            hasStoredNewsAPIKey = false
            newsAPIStatus = "Removed. RSS fallback feeds remain active."
        } catch {
            newsAPIStatus = error.localizedDescription
        }
    }

    private var canSaveMonitoringAPISettings: Bool {
        !monitoringAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasStoredMonitoringAPIToken || !monitoringAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var canTestMonitoringAPIConnection: Bool {
        !monitoringAPIBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasStoredMonitoringAPIToken || !monitoringAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func saveMonitoringAPISettings() {
        do {
            let normalizedURL = try monitoringAPIService.normalizedBaseURL(from: monitoringAPIBaseURL)
            let enteredToken = monitoringAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
            if !enteredToken.isEmpty {
                try monitoringCredentialStore.save(enteredToken)
                monitoringAPIToken = ""
                hasStoredMonitoringAPIToken = true
            }
            monitoringAPIBaseURL = normalizedURL.absoluteString
            monitoringConnectionState = .saved
        } catch {
            monitoringConnectionState = .failed(error.localizedDescription)
        }
    }

    private func removeMonitoringAPIToken() {
        do {
            try monitoringCredentialStore.delete()
            monitoringAPIToken = ""
            hasStoredMonitoringAPIToken = false
            monitoringConnectionState = .notConfigured
        } catch {
            monitoringConnectionState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func testMonitoringAPIConnection() async {
        let enteredToken = monitoringAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let token = enteredToken.isEmpty ? monitoringCredentialStore.read() : enteredToken else {
            monitoringConnectionState = .failed(MonitoringAPIError.missingToken.localizedDescription)
            return
        }

        monitoringConnectionState = .testing
        do {
            let summary = try await monitoringAPIService.summary(
                baseURLText: monitoringAPIBaseURL,
                token: token
            )
            monitoringConnectionState = .connected(summary)
        } catch {
            monitoringConnectionState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        switch await NotificationService().authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = "Authorised"
        case .denied:
            notificationStatus = "Not authorised"
        case .notDetermined:
            notificationStatus = "Not requested"
        @unknown default:
            notificationStatus = "Unknown"
        }
    }
}

private enum MonitoringConnectionState {
    case notTested
    case notConfigured
    case saved
    case testing
    case connected(MonitoringAPISummary)
    case failed(String)

    var isTesting: Bool {
        if case .testing = self { return true }
        return false
    }

    var colour: Color {
        switch self {
        case .connected:
            .green
        case .failed:
            .red
        case .testing:
            .blue
        case .notTested, .notConfigured, .saved:
            .secondary
        }
    }

    var message: String {
        switch self {
        case .notTested:
            "Connection not tested."
        case .notConfigured:
            "Monitoring API is not configured."
        case .saved:
            "Settings saved. Test the connection when ready."
        case .testing:
            "Testing secure connection…"
        case let .connected(summary):
            "Connected — \(summary.sites) sites, \(summary.openIncidents) open incidents, \(summary.openFindings) open findings."
        case let .failed(message):
            message
        }
    }
}
