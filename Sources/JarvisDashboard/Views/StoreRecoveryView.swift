import AppKit
import SwiftUI

/// Shown instead of the dashboard when the data store cannot be opened.
/// It deliberately changes nothing: recovery decisions stay with the user.
struct StoreRecoveryView: View {
    let message: String

    private var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("JARVIS could not open its data", systemImage: "externaldrive.badge.exclamationmark")
                .font(.title2.bold())
            Text("Your tasks and projects have not been changed or deleted. JARVIS stopped before loading them so nothing is overwritten.")
            Text(message)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            Text("Automatic and pre-migration backups are in the JARVIS Dashboard folder. Quit, restore or move the store, then reopen JARVIS.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Backups Folder") {
                    NSWorkspace.shared.open(applicationSupport.appendingPathComponent("JARVIS Dashboard", isDirectory: true))
                }
                Button("Show Data Store") {
                    NSWorkspace.shared.activateFileViewerSelecting([applicationSupport.appendingPathComponent("default.store")])
                }
                Spacer()
                Button("Quit JARVIS") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 300)
    }
}
