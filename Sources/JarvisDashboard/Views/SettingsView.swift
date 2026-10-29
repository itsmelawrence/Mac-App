import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var loginItemService = LoginItemService()
    @State private var notificationStatus = "Not requested"
    @State private var newsAPIKey = ""
    @State private var hasStoredNewsAPIKey = false
    @State private var newsAPIStatus: String?
    @State private var mapTilerKey = ""
    @State private var hasStoredMapTilerKey = false
    @State private var mapTilerStatus: String?
    @AppStorage("icm.vaultPath") private var icmVaultPath = ""
    @AppStorage(SiteMonitor.notificationsKey) private var notifyOnSiteChange = true
    @State private var icmVaultStatus: String?

    private let newsAPIKeyStore = NewsAPIKeyStore()
    private let mapTilerKeyStore = MapTilerKeyStore()

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

            Section("Philippines map · MapTiler preview") {
                SecureField("Paste your MapTiler API key", text: $mapTilerKey)
                    .textContentType(.password)
                HStack {
                    Text(hasStoredMapTilerKey ? "Key stored in macOS Keychain." : "No key stored. Apple Maps remains available.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if hasStoredMapTilerKey {
                        Button("Remove", role: .destructive) { removeMapTilerKey() }
                    }
                    Button("Save") { saveMapTilerKey() }
                        .disabled(mapTilerKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Use a MapTiler API key, never a service token. The preview loads MapTiler's landscape map over the internet; map sessions and tile requests count towards your plan's allowance. The key is sent to MapTiler while the preview is open.")
                    .font(.caption).foregroundStyle(.secondary)
                if let mapTilerStatus {
                    Text(mapTilerStatus).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Website checks") {
                Toggle("Notify me when a site goes down or recovers", isOn: $notifyOnSiteChange)
                Text("While JARVIS is open, it requests each project's website every 5 minutes from this Mac. A site counts as down after two failed checks in a row, a minute apart. Checks pause while the Mac sleeps or is offline. Add a website to a project in Projects.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("ICM · Obsidian vault") {
                LabeledContent("Vault", value: ICMRoutingService.vaultURL(configuredPath: icmVaultPath).path)
                    .textSelection(.enabled)
                HStack {
                    Button("Choose Projects vault") { chooseICMVault() }
                    if let icmVaultStatus {
                        Text(icmVaultStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("JARVIS reads CONTEXT.md and ICM/routes.json to route work requests. The command console saves submitted prompts under Memory/01_intake. Graphify notes are navigation hints.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Data, backup and restore") {
                BackupSettingsView()
            }

            Section("Data and privacy") {
                Text("Tasks, projects, locations, and backups are stored locally. NewsAPI.org and MapTiler keys are stored in macOS Keychain and excluded from backups and exports. Live services receive only the information required for their requests. Website checks are plain requests sent from this Mac to each project's site.")
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
            hasStoredMapTilerKey = mapTilerKeyStore.read() != nil
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

    private func saveMapTilerKey() {
        do {
            try mapTilerKeyStore.save(mapTilerKey)
            mapTilerKey = ""
            hasStoredMapTilerKey = true
            mapTilerStatus = "Saved. Select MapTiler preview on the Philippines map."
            NotificationCenter.default.post(name: .mapTilerKeyChanged, object: nil)
        } catch {
            mapTilerStatus = error.localizedDescription
        }
    }

    private func chooseICMVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Vault"
        panel.directoryURL = ICMRoutingService.vaultURL(configuredPath: icmVaultPath)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let hasRouter = FileManager.default.fileExists(atPath: url.appendingPathComponent("CONTEXT.md").path)
        let hasRoutes = FileManager.default.fileExists(atPath: url.appendingPathComponent("ICM/routes.json").path)
        guard hasRouter && hasRoutes else {
            icmVaultStatus = "Choose the Projects vault containing CONTEXT.md and ICM/routes.json."
            return
        }
        icmVaultPath = url.path
        icmVaultStatus = "Vault ready."
    }

    private func removeMapTilerKey() {
        do {
            try mapTilerKeyStore.delete()
            mapTilerKey = ""
            hasStoredMapTilerKey = false
            mapTilerStatus = "Removed. The Philippines map will use Apple Maps."
            UserDefaults.standard.set("Apple Maps", forKey: "weatherMap.provider")
            NotificationCenter.default.post(name: .mapTilerKeyChanged, object: nil)
        } catch {
            mapTilerStatus = error.localizedDescription
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
