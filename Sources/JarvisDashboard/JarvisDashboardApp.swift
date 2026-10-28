import AppKit
import SwiftData
import SwiftUI

@main
struct JarvisDashboardApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var wakeMonitor = WakeMonitor()
    @StateObject private var speechService = SpeechService.shared
    @StateObject private var backupCoordinator = BackupCoordinator()

    private let modelContainer: ModelContainer

    init() {
        do {
            try MigrationSafetyBackup.createIfNeeded(targetVersion: "1.0.0")
            modelContainer = try JarvisDataStore.makeContainer()
        } catch {
            fatalError("Unable to create the JARVIS data store: \(error.localizedDescription)")
        }
        // App lifetime, not a view: the menu-bar app keeps running with its window closed.
        Task { await VaultMaintenanceService.runWhileAppIsOpen() }
    }

    var body: some Scene {
        WindowGroup("JARVIS Dashboard", id: "dashboard") {
            RootView()
                .environmentObject(appState)
                .environmentObject(wakeMonitor)
                .environmentObject(speechService)
                .environmentObject(backupCoordinator)
                .task {
                    wakeMonitor.start { sleepDuration in
                        guard appState.showWakeBriefing,
                              sleepDuration >= appState.minimumSleepForBriefing else { return }
                        appState.requestBriefing(reason: .wake)
                    }
                }
                .onReceive(appState.$briefingRequest.compactMap { $0 }) { request in
                    BriefingPanelController.shared.show(reason: request.reason, message: request.message)
                    appState.consumeBriefingRequest(request)
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .modelContainer(modelContainer)

        MenuBarExtra("JARVIS", systemImage: "sparkles.rectangle.stack") {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(speechService)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(speechService)
                .modelContainer(modelContainer)
        }
    }
}
