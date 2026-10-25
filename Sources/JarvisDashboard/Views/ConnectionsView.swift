import AppKit
import Combine
import SwiftUI

struct ConnectionsView: View {
    @AppStorage("icm.vaultPath") private var vaultPath = ""
    @State private var projects: [ConnectionProject] = []
    @State private var selectedProjectID: String?
    @State private var selectedFile: ConnectionFile?
    @State private var query = ""
    @State private var searchResults: [ConnectionFile] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private var vaultURL: URL { ICMRoutingService.vaultURL(configuredPath: vaultPath) }
    private var project: ConnectionProject? { projects.first { $0.id == selectedProjectID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cortex").font(.title2.bold())
                    Text("Your workspace memory and source connections.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: reload)
            }
            .padding(18)
            Divider()
            if let errorMessage {
                ContentUnavailableView("Vault unavailable", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text(errorMessage))
            } else if projects.isEmpty {
                ContentUnavailableView("No projects found", systemImage: "square.stack.3d.up",
                                       description: Text("Add a project under Work or Personal in the selected vault."))
            } else if let project {
                HSplitView {
                    browser(for: project)
                        .frame(minWidth: 280, idealWidth: 340, maxWidth: 450)
                    detail(for: project)
                        .frame(minWidth: 450)
                }
            } else {
                overview
            }
        }
        .navigationTitle("Cortex")
        .onAppear(perform: reload)
        .onChange(of: vaultPath) { _, _ in reload() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if selectedProjectID == nil { reload() }
        }
    }

    private func browser(for project: ConnectionProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Project", selection: $selectedProjectID) {
                Text("All projects").tag(Optional<String>.none)
                ForEach(projects) { item in Text(item.name).tag(Optional(item.id)) }
            }
            .onChange(of: selectedProjectID) { _, _ in
                selectedFile = nil
                searchResults = []
                isSearching = false
            }
            HStack {
                TextField("Find a folder or file", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch(in: project) }
                Button("Search", systemImage: "magnifyingglass") { runSearch(in: project) }
                    .labelStyle(.iconOnly)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isSearching {
                HStack {
                    Text("\(searchResults.count) matches\(searchResults.count == 100 ? " · first 100" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show tree") { isSearching = false; query = "" }
                        .font(.caption)
                }
            } else {
                Text("SOURCE TREE · generated and dependency folders excluded")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if isSearching {
                        ForEach(searchResults) { item in
                            fileButton(item, indent: 0)
                        }
                    } else {
                        ForEach(ConnectionsService.children(of: project.rootURL, in: project)) { item in
                            ConnectionTreeRow(item: item, project: project, selectedURL: selectedFile?.url) {
                                selectedFile = $0
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Workspace map").font(.title3.bold())
                Text("\(projects.count) projects found · choose one to inspect its source tree and connections.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.cyan)
                    Text("Obsidian Projects vault").font(.headline)
                    Spacer()
                    Button("Open vault") { NSWorkspace.shared.open(vaultURL) }
                }
                .padding(16)
                .background(Color.cyan.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                ForEach(projects) { item in
                    Button { selectedProjectID = item.id } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.title2).foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).font(.headline)
                                Text(item.route.projectPath).font(.caption).foregroundStyle(.secondary)
                                Text(item.isRegistered ? "ICM route" : "Discovered from vault")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(FileManager.default.fileExists(atPath: item.graphURL.path)
                                     ? "Graphify export available" : "No Graphify export yet")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                Text("Projects under Work and Personal appear automatically when they contain a source marker such as Git, a project manifest, or an index file. ICM/routes.json adds command handoff context. Each project view omits hidden, generated and dependency folders.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func fileButton(_ item: ConnectionFile, indent: CGFloat) -> some View {
        Button {
            selectedFile = item
        } label: {
            HStack(spacing: 7) {
                Image(systemName: item.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(item.isDirectory ? .cyan : .secondary)
                Text(item.relativePath).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .padding(.leading, indent)
            .padding(.horizontal, 7).padding(.vertical, 6)
            .background(selectedFile?.url == item.url ? Color.cyan.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func detail(for project: ConnectionProject) -> some View {
        let notes = ConnectionsService.notes(for: selectedFile, in: project, vaultURL: vaultURL)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedFile?.name ?? project.name).font(.title3.bold())
                        Text(selectedFile?.relativePath ?? project.rootURL.path)
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Open in Finder", systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.activateFileViewerSelecting([selectedFile?.url ?? project.rootURL])
                    }
                }
                Text("SYNAPSE MAP").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                GraphifyHTMLView(
                    htmlURL: GraphifyHTMLService.htmlURL(for: project, vaultURL: vaultURL),
                    focusSourcePath: selectedFile?.isDirectory == false ? selectedFile?.relativePath : nil
                )
                .frame(height: 570)
                HStack {
                    Text("KNOWN CONNECTIONS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(notes.count) notes").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(notes) { note in
                    HStack(spacing: 10) {
                        Image(systemName: "link").foregroundStyle(.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title).font(.subheadline.weight(.medium))
                            Text(note.relation).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") { NSWorkspace.shared.open(note.url) }
                            .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                }
                if notes.count <= 1 && selectedFile != nil {
                    Text("No file-specific Graphify note was found. Refresh the local Graphify export to add code connections.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Graphify connections are navigation hints. Verify a relationship in the current source before using it for a change.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func reload() {
        do {
            projects = try ConnectionsService.projects(in: vaultURL)
            if !projects.contains(where: { $0.id == selectedProjectID }) { selectedProjectID = nil }
            selectedFile = nil
            searchResults = []
            isSearching = false
            errorMessage = nil
        } catch {
            projects = []
            errorMessage = error.localizedDescription
        }
    }

    private func runSearch(in project: ConnectionProject) {
        searchResults = ConnectionsService.search(query, in: project)
        isSearching = true
    }
}

private struct ConnectionTreeRow: View {
    let item: ConnectionFile
    let project: ConnectionProject
    let selectedURL: URL?
    let onSelect: (ConnectionFile) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if item.isDirectory {
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .frame(width: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12, height: 12)
                }
                Button { onSelect(item) } label: {
                    Label(item.name, systemImage: item.isDirectory ? "folder" : "doc.text")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(selectedURL == item.url ? Color.cyan.opacity(0.16) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            if expanded && item.isDirectory {
                ForEach(ConnectionsService.children(of: item.url, in: project)) { child in
                    ConnectionTreeRow(item: child, project: project, selectedURL: selectedURL, onSelect: onSelect)
                        .padding(.leading, 15)
                }
            }
        }
    }
}
