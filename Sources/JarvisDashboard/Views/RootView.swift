import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(SidebarDestination.allCases, selection: $appState.selection) { destination in
                Label(destination.title, systemImage: destination.systemImage)
                    .tag(destination)
            }
            .navigationTitle("JARVIS")
            .navigationSplitViewColumnWidth(min: 190, ideal: 215)
        } detail: {
            switch appState.selection ?? .today {
            case .today:
                TodayView()
            case .tasks:
                TasksView()
            case .projects:
                ProjectsView()
            case .intelligence:
                IntelligenceView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}
