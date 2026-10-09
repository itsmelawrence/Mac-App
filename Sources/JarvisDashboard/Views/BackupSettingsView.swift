import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("backup.retentionCount") private var retentionCount = 14

    @State private var exportFile: JarvisBackupFile?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImport: PendingJarvisImport?
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var backupFolder = "Loading…"
    @State private var lastBackupAt: Date?

    private let service = JarvisBackupService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export includes tasks, projects, saved locations, and non-secret preferences. API keys, monitoring tokens, and reporter tokens are never included.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Export Data…") { exportData() }
                Button("Import or Restore…") { showingImporter = true }
                Spacer()
                if let lastBackupAt {
                    Text("Last backup: \(lastBackupAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No automatic backup yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            LabeledContent("Backup folder") {
                Text(backupFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 330, alignment: .trailing)
            }

            HStack {
                Button("Back Up Now") { backUpNow() }
                Button("Choose Folder…") { chooseFolder() }
                Button("Reveal in Finder") { revealBackups() }
                Spacer()
                Stepper("Keep \(retentionCount) backups", value: $retentionCount, in: 1...60)
                    .frame(width: 190)
            }

            Text("JARVIS creates a snapshot once per day and before data-schema migrations. Restoring on another Mac requires you to reconnect local repositories and re-enter all API and reporter tokens.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(isError ? .red : .secondary)
            }
        }
        .onAppear { refreshState() }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportFile,
            contentType: UTType(filenameExtension: "jarvisbackup") ?? .json,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                showStatus("Export complete. Credentials remain in Keychain and were not included.")
            case let .failure(error):
                showError(error)
            }
            exportFile = nil
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: JarvisBackupFile.readableContentTypes,
            allowsMultipleSelection: false
        ) { result in
            importFile(result)
        }
        .sheet(item: $pendingImport) { pending in
            ImportPreviewView(pending: pending) { mode, confirmation in
                applyImport(pending, mode: mode, confirmation: confirmation)
            }
        }
    }

    private var exportFilename: String {
        "JARVIS-Export-\(Date.now.formatted(.iso8601.year().month().day()))"
    }

    private func exportData() {
        do {
            exportFile = JarvisBackupFile(data: try service.encode(service.makeDocument(context: modelContext)))
            showingExporter = true
        } catch {
            showError(error)
        }
    }

    private func importFile(_ result: Result<[URL], Error>) {
        do {
            let url = try result.get().first
            guard let url else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let document = try service.decode(Data(contentsOf: url))
            let preview = try service.preview(document, context: modelContext)
            pendingImport = PendingJarvisImport(document: document, preview: preview)
        } catch {
            showError(error)
        }
    }

    private func applyImport(
        _ pending: PendingJarvisImport,
        mode: JarvisImportMode,
        confirmation: String
    ) {
        do {
            try service.apply(
                pending.document,
                mode: mode,
                confirmation: confirmation,
                context: modelContext,
                retentionCount: retentionCount
            )
            pendingImport = nil
            refreshState()
            showStatus(mode == .merge
                ? "Import merged successfully. Existing record identifiers were preserved."
                : "Data replaced successfully. A safety backup was created first.")
        } catch {
            showError(error)
        }
    }

    private func backUpNow() {
        do {
            let url = try service.backupNow(context: modelContext, retentionCount: retentionCount)
            refreshState()
            showStatus("Backup created: \(url.lastPathComponent)")
        } catch {
            showError(error)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose JARVIS Backup Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        service.setBackupFolder(url)
        refreshState()
        showStatus("Future automatic backups will be written to this folder.")
    }

    private func revealBackups() {
        do {
            let folder = try service.backupFolderURL()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            showError(error)
        }
    }

    private func refreshState() {
        lastBackupAt = UserDefaults.standard.object(forKey: "backup.lastBackupAt") as? Date
        backupFolder = (try? service.backupFolderURL().path) ?? "Unavailable"
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        isError = false
    }

    private func showError(_ error: Error) {
        statusMessage = error.localizedDescription
        isError = true
    }
}

private struct PendingJarvisImport: Identifiable {
    let id = UUID()
    let document: JarvisBackupDocument
    let preview: JarvisImportPreview
}

private struct ImportPreviewView: View {
    let pending: PendingJarvisImport
    let apply: (JarvisImportMode, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var replaceConfirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Import")
                        .font(.title2.bold())
                    Text("Exported by JARVIS \(pending.document.appVersion) on \(pending.document.exportedAt.formatted(date: .abbreviated, time: .shortened)).")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
            }

            Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 10) {
                GridRow {
                    Text("Data").bold()
                    Text("New").bold()
                    Text("Updated").bold()
                    Text("Skipped").bold()
                }
                previewRow("Tasks", pending.preview.tasks)
                previewRow("Projects", pending.preview.projects)
                previewRow("Locations", pending.preview.locations)
            }

            Text("\(pending.preview.changedPreferences) preference values differ. Merge updates matching stable IDs and never duplicates them.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Merge") { apply(.merge, "") }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                TextField("Type REPLACE", text: $replaceConfirmation)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button("Replace All", role: .destructive) {
                    apply(.replace, replaceConfirmation)
                }
                .disabled(replaceConfirmation != "REPLACE")
            }

            Text("Replace deletes current local records after creating a safety backup. Credentials are never restored; enter them again in Settings on a new Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 600)
    }

    private func previewRow(_ title: String, _ preview: ImportEntityPreview) -> some View {
        GridRow {
            Text(title)
            Text("\(preview.new)")
            Text("\(preview.updated)")
            Text("\(preview.skipped)")
        }
    }
}
