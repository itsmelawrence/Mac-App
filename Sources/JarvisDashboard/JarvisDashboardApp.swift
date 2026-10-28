import AppKit
import SwiftData
import SwiftUI

@main
struct JarvisDashboardApp: App {
    @StateObject private var appState: AppState
    @StateObject private var wakeMonitor: WakeMonitor
    @StateObject private var speechService = SpeechService.shared
    @StateObject private var backupCoordinator: BackupCoordinator

    /// nil when the store could not be opened; the UI then shows StoreRecoveryView.
    private let modelContainer: ModelContainer?
    private let storeError: String?
    private let coordinator: AppCoordinator?

    init() {
        let appState = AppState()
        let wakeMonitor = WakeMonitor()
        let backupCoordinator = BackupCoordinator()
        _appState = StateObject(wrappedValue: appState)
        _wakeMonitor = StateObject(wrappedValue: wakeMonitor)
        _backupCoordinator = StateObject(wrappedValue: backupCoordinator)

        do {
            try MigrationSafetyBackup.createIfNeeded(targetVersion: "1.0.0")
            let container = try JarvisDataStore.makeContainer()
            modelContainer = container
            storeError = nil
            // App-lifetime work starts here, not in a window, so it runs with the window closed.
            let coordinator = AppCoordinator(
                appState: appState, wakeMonitor: wakeMonitor,
                backupCoordinator: backupCoordinator, container: container
            )
            coordinator.start()
            self.coordinator = coordinator
        } catch {
            // Previously fatalError: a crash loop on every launch with no way to reach backups.
            modelContainer = nil
            storeError = error.localizedDescription
            coordinator = nil
        }
    }

    var body: some Scene {
        WindowGroup("JARVIS Dashboard", id: "dashboard") {
            if let modelContainer {
                RootView()
                    .environmentObject(appState)
                    .environmentObject(wakeMonitor)
                    .environmentObject(speechService)
                    .environmentObject(backupCoordinator)
                    .modelContainer(modelContainer)
            } else {
                StoreRecoveryView(message: storeError ?? "Unknown error")
            }
        }
        .defaultSize(width: 1_180, height: 760)

        MenuBarExtra("JARVIS", systemImage: "sparkles.rectangle.stack") {
            if let modelContainer {
                MenuBarView()
                    .environmentObject(appState)
                    .environmentObject(speechService)
                    .modelContainer(modelContainer)
            } else {
                StoreRecoveryView(message: storeError ?? "Unknown error")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            if let modelContainer {
                SettingsView()
                    .environmentObject(appState)
                    .environmentObject(speechService)
                    .modelContainer(modelContainer)
            } else {
                StoreRecoveryView(message: storeError ?? "Unknown error")
            }
        }
    }
}
