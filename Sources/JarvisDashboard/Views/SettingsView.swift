import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var loginItemService = LoginItemService()
    @State private var notificationStatus = "Not requested"
    @State private var newsAPIKey = ""
    @State private var hasStoredNewsAPIKey = false
    @State private var newsAPIStatus: String?

    private let newsAPIKeyStore = NewsAPIKeyStore()

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

            Section("Data and privacy") {
                Text("Tasks and projects are stored locally. The NewsAPI.org key is stored in macOS Keychain. Live services receive only the information required for their requests.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(minWidth: 560, minHeight: 440)
        .navigationTitle("Settings")
        .onAppear {
            loginItemService.refresh()
            hasStoredNewsAPIKey = newsAPIKeyStore.read() != nil
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
