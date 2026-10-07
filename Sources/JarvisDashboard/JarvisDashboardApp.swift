import AppKit
import SwiftData
import SwiftUI

@main
struct JarvisDashboardApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var wakeMonitor = WakeMonitor()

    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: TaskItem.self, ProjectItem.self, SavedLocation.self)
        } catch {
            fatalError("Unable to create the JARVIS data store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup("JARVIS Dashboard", id: "dashboard") {
            RootView()
                .environmentObject(appState)
                .environmentObject(wakeMonitor)
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
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
