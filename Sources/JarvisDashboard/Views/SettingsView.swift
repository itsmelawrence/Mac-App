import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var loginItemService = LoginItemService()
    @AppStorage("settings.tab") private var tabRawValue = SettingsTab.general.rawValue
    @State private var notificationStatus = NotificationAccess.notRequested
    @State private var newsAPIKey = ""
    @State private var storedNewsAPIKey: String?
    @State private var newsAPIStatus: String?
    @State private var mapTilerKey = ""
    @State private var storedMapTilerKey: String?
    @State private var mapTilerStatus: String?
    @AppStorage("icm.vaultPath") private var icmVaultPath = ""
    @AppStorage(SiteMonitor.notificationsKey) private var notifyOnSiteChange = true
    @State private var icmVaultStatus: String?

    private let newsAPIKeyStore = NewsAPIKeyStore()
    private let mapTilerKeyStore = MapTilerKeyStore()

    private var tab: SettingsTab { SettingsTab(rawValue: tabRawValue) ?? .general }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                switch tab {
                case .general: generalSections
                case .voice: voiceSections
                case .connections: connectionSections
                case .data: dataSections
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .frame(minWidth: 620, minHeight: 600)
        .background(
            LinearGradient(
                colors: [Color(red: 0.012, green: 0.028, blue: 0.052), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Settings")
        .onAppear {
            loginItemService.refresh()
            storedNewsAPIKey = newsAPIKeyStore.read()
            storedMapTilerKey = mapTilerKeyStore.read()
        }
        .task { await refreshNotificationStatus() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(tab.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Picker("Section", selection: $tabRawValue) {
                ForEach(SettingsTab.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
        .padding(.top, 32)
        .padding(.bottom, 4)
    }

    // MARK: General

    @ViewBuilder
    private var generalSections: some View {
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

        Section {
            LabeledContent("Notifications") {
                HStack(spacing: 10) {
                    Label(notificationStatus.title, systemImage: notificationStatus.systemImage)
                        .foregroundStyle(notificationStatus.tint)
                    switch notificationStatus {
                    case .allowed:
                        EmptyView()
                    case .notRequested, .failed:
                        Button("Allow Notifications") { requestNotifications() }
                    case .denied:
                        Button("Open System Settings") { openNotificationSettings() }
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Used for site outages and recoveries, critical intelligence alerts, and task reminders.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Briefing & voice

    @ViewBuilder
    private var voiceSections: some View {
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

        Section {
            Toggle("Enable text to speech", isOn: $speechService.isEnabled)
            Group {
                Toggle("Speak wake briefings automatically", isOn: $speechService.speakWakeBriefings)
                Toggle("Speak new critical intelligence alerts", isOn: $speechService.speakCriticalAlerts)

                Picker("Voice", selection: $speechService.voiceIdentifier) {
                    Text("British English · macOS default").tag("")
                    ForEach(speechService.availableVoices) { voice in
                        Text("\(voice.name) · \(voice.language)").tag(voice.id)
                    }
                }

                LabeledContent("Speaking rate") {
                    Slider(value: $speechService.rate, in: 0.35...0.62) {
                        Text("Speaking rate")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise").help("Slower")
                    } maximumValueLabel: {
                        Image(systemName: "hare").help("Faster")
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }

                LabeledContent("Pitch") {
                    Slider(value: $speechService.pitch, in: 0.7...1.3) {
                        Text("Pitch")
                    } minimumValueLabel: {
                        Text("Low").font(.caption)
                    } maximumValueLabel: {
                        Text("High").font(.caption)
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }

                LabeledContent("Volume") {
                    Slider(value: $speechService.volume, in: 0...1) {
                        Text("Volume")
                    } minimumValueLabel: {
                        Image(systemName: "speaker.fill")
                    } maximumValueLabel: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
            }
            .disabled(!speechService.isEnabled)

            HStack {
                Button(speechService.isSpeaking ? "Stop" : "Preview Voice",
                       systemImage: speechService.isSpeaking ? "stop.fill" : "play.fill") {
                    if speechService.isSpeaking { speechService.stop() } else { speechService.preview() }
                }
                .disabled(!speechService.isEnabled && !speechService.isSpeaking)
                Spacer()
            }
        } header: {
            Text("JARVIS voice")
        } footer: {
            Text("Speech is generated locally by macOS.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            Toggle("Stay silent during quiet hours", isOn: $speechService.quietHoursEnabled)
            Group {
                Picker("From", selection: $speechService.quietStartHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Until", selection: $speechService.quietEndHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
            }
            .disabled(!speechService.quietHoursEnabled)
        } header: {
            Text("Quiet hours")
        }
        .disabled(!speechService.isEnabled)
    }

    // MARK: Connections

    @ViewBuilder
    private var connectionSections: some View {
        Section {
            APIKeyRows(
                placeholder: "Paste your NewsAPI.org key",
                storedKey: storedNewsAPIKey,
                draft: $newsAPIKey,
                save: saveNewsAPIKey,
                remove: removeNewsAPIKey
            )
            if let newsAPIStatus {
                Text(newsAPIStatus).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("News")
        } footer: {
            Text(storedNewsAPIKey == nil
                 ? "Without a key, JARVIS uses RSS feeds. The key is stored in macOS Keychain."
                 : "Headlines come from NewsAPI.org. The key is stored in macOS Keychain.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            APIKeyRows(
                placeholder: "Paste your MapTiler API key",
                storedKey: storedMapTilerKey,
                draft: $mapTilerKey,
                save: saveMapTilerKey,
                remove: removeMapTilerKey
            )
            if let mapTilerStatus {
                Text(mapTilerStatus).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Map tiles (MapTiler)")
        } footer: {
            Text("Optional landscape tiles for the Philippines map; without a key, Apple Maps is used. Use an API key, never a service token. The key is sent to MapTiler while the preview is open, and map sessions count towards your plan's allowance.")
                .font(.caption).foregroundStyle(.secondary)
        }

        LeadSourceSettings()

        Section {
            Toggle("Notify me when a site goes down or recovers", isOn: $notifyOnSiteChange)
        } header: {
            Text("Website checks")
        } footer: {
            Text("While JARVIS is open, it requests each project's website every 5 minutes from this Mac. A site counts as down after two failed checks in a row, a minute apart. Checks pause while the Mac sleeps or is offline. Add a website to a project in Projects.")
                .font(.caption).foregroundStyle(.secondary)
        }

        Section {
            LabeledContent("Vault") {
                HStack(spacing: 10) {
                    Text(abbreviatedPath(ICMRoutingService.vaultURL(configuredPath: icmVaultPath).path))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                    Button("Change…") { chooseICMVault() }
                }
            }
            if let icmVaultStatus {
                Text(icmVaultStatus).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Obsidian vault")
        } footer: {
            Text("JARVIS reads CONTEXT.md and ICM/routes.json to route work requests. The command console saves submitted prompts under Memory/01_intake. Graphify notes are navigation hints.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Data

    @ViewBuilder
    private var dataSections: some View {
        BackupSettingsView()

        Section("Privacy") {
            Text("Tasks, projects, locations, and backups are stored locally. NewsAPI.org and MapTiler keys are stored in macOS Keychain and excluded from backups and exports. Live services receive only the information required for their requests. Website checks are plain requests sent from this Mac to each project's site.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func saveNewsAPIKey() {
        do {
            try newsAPIKeyStore.save(newsAPIKey)
            storedNewsAPIKey = newsAPIKeyStore.read()
            newsAPIKey = ""
            newsAPIStatus = "Saved. NewsAPI.org will be used on the next refresh."
        } catch {
            newsAPIStatus = error.localizedDescription
        }
    }

    private func saveMapTilerKey() {
        do {
            try mapTilerKeyStore.save(mapTilerKey)
            storedMapTilerKey = mapTilerKeyStore.read()
            mapTilerKey = ""
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
        icmVaultStatus = nil
    }

    private func removeMapTilerKey() {
        do {
            try mapTilerKeyStore.delete()
            mapTilerKey = ""
            storedMapTilerKey = nil
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
            storedNewsAPIKey = nil
            newsAPIStatus = "Removed. RSS fallback feeds remain active."
        } catch {
            newsAPIStatus = error.localizedDescription
        }
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func requestNotifications() {
        Task {
            do {
                let granted = try await NotificationService().requestAuthorization()
                notificationStatus = granted ? .allowed : .denied
            } catch {
                notificationStatus = .failed
            }
        }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        switch await NotificationService().authorizationStatus() {
        case .authorized, .provisional, .ephemeral:
            notificationStatus = .allowed
        case .denied:
            notificationStatus = .denied
        case .notDetermined:
            notificationStatus = .notRequested
        @unknown default:
            notificationStatus = .notRequested
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, voice, connections, data

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .voice: "Briefing & Voice"
        case .connections: "Connections"
        case .data: "Data"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .voice: "waveform"
        case .connections: "link"
        case .data: "externaldrive"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Startup and notification permission."
        case .voice: "The wake briefing and how JARVIS speaks."
        case .connections: "News, map tiles, leads, website checks, and your Obsidian vault."
        case .data: "Backups, exports, and what stays on this Mac."
        }
    }
}

private enum NotificationAccess {
    case notRequested, allowed, denied, failed

    var title: String {
        switch self {
        case .notRequested: "Not requested"
        case .allowed: "Allowed"
        case .denied: "Turned off in System Settings"
        case .failed: "Request failed"
        }
    }

    var systemImage: String {
        switch self {
        case .notRequested: "bell"
        case .allowed: "checkmark.circle.fill"
        case .denied: "bell.slash.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notRequested: .secondary
        case .allowed: .green
        case .denied, .failed: .orange
        }
    }
}

/// A Keychain-backed key: "Saved · ••••abcd" with Replace and Remove once stored, otherwise a field to paste one.
private struct APIKeyRows: View {
    let placeholder: String
    let storedKey: String?
    @Binding var draft: String
    let save: () -> Void
    let remove: () -> Void
    @State private var isReplacing = false

    private var canSave: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        if let storedKey, !isReplacing {
            LabeledContent("API key") {
                HStack(spacing: 10) {
                    Label("Saved · ••••\(storedKey.suffix(4))", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Replace…") { isReplacing = true }
                    Button("Remove", role: .destructive, action: remove)
                }
            }
        } else {
            LabeledContent("API key") {
                HStack(spacing: 10) {
                    SecureField("API key", text: $draft, prompt: Text(placeholder))
                        .textContentType(.password)
                        .labelsHidden()
                        .frame(maxWidth: 280)
                        .onSubmit { if canSave { commit() } }
                    if isReplacing {
                        Button("Cancel") {
                            draft = ""
                            isReplacing = false
                        }
                    }
                    Button("Save", action: commit)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func commit() {
        save()
        isReplacing = false
    }
}
