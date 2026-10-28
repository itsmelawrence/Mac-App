import Foundation
import SwiftData
import Testing
@testable import JarvisDashboard

@MainActor
struct AppCoordinatorTests {
    private func makeCoordinator(recording presented: @escaping (AppState.BriefingReason) -> Void) throws -> (AppCoordinator, AppState) {
        let configuration = ModelConfiguration(schema: JarvisDataStore.schema, isStoredInMemoryOnly: true)
        let container = try JarvisDataStore.makeContainer(configuration: configuration)
        let appState = AppState()
        let coordinator = AppCoordinator(
            appState: appState, wakeMonitor: WakeMonitor(), backupCoordinator: BackupCoordinator(),
            container: container, presentBriefing: { reason, _ in presented(reason) }
        )
        return (coordinator, appState)
    }

    @Test func briefingIsPresentedOnceWithoutAnyWindow() async throws {
        var presented: [AppState.BriefingReason] = []
        let (coordinator, appState) = try makeCoordinator { presented.append($0) }
        coordinator.start(runBackgroundJobs: false)
        coordinator.start(runBackgroundJobs: false)  // A second start must not add a second presenter.

        appState.requestBriefing(reason: .manual)
        try await Task.sleep(for: .milliseconds(50))
        #expect(presented == [.manual])
        #expect(appState.briefingRequest == nil)

        appState.requestBriefing(reason: .wake)
        try await Task.sleep(for: .milliseconds(50))
        #expect(presented == [.manual, .wake])
    }
}
