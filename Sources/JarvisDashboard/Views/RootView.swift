import AppKit
import SwiftData
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
            case .connections:
                ConnectionsView()
            case .intelligence:
                IntelligenceView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowFirstPaintConfigurator())
        // Automatic backups run in AppCoordinator, so they continue with this window closed.
    }
}

private struct WindowFirstPaintConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowObserverView {
        WindowObserverView()
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {}

    final class WindowObserverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.backgroundColor = NSColor(
                calibratedRed: 2 / 255,
                green: 6 / 255,
                blue: 12 / 255,
                alpha: 1
            )
            window.isOpaque = true
        }
    }
}
