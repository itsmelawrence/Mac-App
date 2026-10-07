import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var splashOpacity = 1.0

    var body: some View {
        ZStack {
            Color(red: 2 / 255, green: 6 / 255, blue: 12 / 255)
                .ignoresSafeArea()

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

            if appState.isSplashVisible {
                StartupSplashView {
                    appState.markSplashAnimationFinished()
                }
                .opacity(splashOpacity)
                .ignoresSafeArea()
                .zIndex(100)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowFirstPaintConfigurator())
        .onChange(of: appState.canDismissSplash) { _, canDismiss in
            guard canDismiss else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                splashOpacity = 0
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                appState.completeSplash()
            }
        }
    }
}
