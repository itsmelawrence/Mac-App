import Foundation
import Testing
@testable import JarvisDashboard

struct AppStateTests {
    @Test @MainActor func projectRequestNavigatesAndCanBeConsumed() {
        let appState = AppState()
        let projectID = UUID()

        appState.openProject(projectID)
        #expect(appState.selection == .projects)
        #expect(appState.requestedProjectID == projectID)

        appState.consumeProjectRequest(UUID())
        #expect(appState.requestedProjectID == projectID)

        appState.consumeProjectRequest(projectID)
        #expect(appState.requestedProjectID == nil)
    }
}
