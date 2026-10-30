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
    @State private var routeIssues: [String] = []
    @State private var health: VaultHealth?
    @State private var isReloading = false
    @State private var mappedIDs: Set<String> = []
    @State private var scope = CortexScope.all
    @State private var searchText = ""
    @State private var collapsedGroups: Set<String> = []
    @State private var showingVaultIssues = false
    @AppStorage("cortex.layout") private var layout: CollectionLayout = .list

    private var vaultURL: URL { ICMRoutingService.vaultURL(configuredPath: vaultPath) }
    private var project: ConnectionProject? { projects.first { $0.id == selectedProjectID } }

    var body: some View {
        Group {
            if errorMessage == nil, !projects.isEmpty, project == nil {
                overview
            } else {
                compactLayout
            }
        }
        .navigationTitle("Cortex")
        .onAppear(perform: reload)
        .onChange(of: vaultPath) { _, _ in reload() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            if selectedProjectID == nil { reload() }
        }
    }

    /// Errors, the empty state, and a selected project's split view.
    private var compactLayout: some View {
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
            }
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

    // MARK: Overview

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                overviewHeader
                statusRail
                listSection
                Text("Projects under Work and Personal appear automatically when they contain a source marker such as Git, a project manifest, or an index file. ICM/routes.json adds command handoff context. Each project view omits hidden, generated and dependency folders.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1_180)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.012, green: 0.028, blue: 0.052), Color(nsColor: .windowBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .searchable(text: $searchText, prompt: "Search projects or paths")
    }

    private var overviewHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Cortex")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("\(projects.count) projects · \(mappedIDs.count) mapped · \(projects.count - mappedIDs.count) without a map")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            vaultCapsule
            Button("Open Vault", systemImage: "square.stack.3d.up") { NSWorkspace.shared.open(vaultURL) }
            Button("Refresh", systemImage: "arrow.clockwise", action: reload)
                .labelStyle(.iconOnly)
                .disabled(isReloading)
                .help("Rescan the vault")
        }
    }

    private var statusRail: some View {
        let registered = projects.filter(\.isRegistered).count
        return HStack(spacing: 0) {
            ProjectMetric(title: "Projects", value: "\(projects.count)", tint: .primary)
            ProjectMetricDivider()
            ProjectMetric(title: "Mapped by Graphify", value: "\(mappedIDs.count)",
                          tint: mappedIDs.isEmpty ? .secondary : .cyan)
            ProjectMetricDivider()
            ProjectMetric(title: "Without a map", value: "\(projects.count - mappedIDs.count)", tint: .secondary)
            ProjectMetricDivider()
            ProjectMetric(title: "ICM routes", value: "\(registered)", tint: registered > 0 ? .primary : .secondary)
            ProjectMetricDivider()
            ProjectMetric(title: "Vault checked",
                          value: health.map { $0.checkedAt.formatted(.relative(presentation: .named)) } ?? "—",
                          tint: vaultIsStale ? .orange : .secondary)
        }
        .padding(.vertical, 18)
        .projectSurface(cornerRadius: 16)
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(CortexScope.allCases) { item in
                    CortexScopeChip(scope: item, count: count(for: item), isSelected: scope == item) {
                        scope = item
                    }
                }
                Spacer(minLength: 0)
                CollectionLayoutPicker(layout: $layout)
            }
            let groups = visibleGroups
            if groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 32)).foregroundStyle(.tertiary)
                    Text("No matching projects").font(.headline)
                    Text("Try a broader search or another filter.").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .projectSurface(cornerRadius: 16)
            } else {
                ForEach(groups) { group in
                    groupSection(group)
                }
            }
        }
    }

    private func groupSection(_ group: CortexGroup) -> some View {
        let isCollapsed = collapsedGroups.contains(group.id) && searchText.isEmpty
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if collapsedGroups.contains(group.id) { collapsedGroups.remove(group.id) } else { collapsedGroups.insert(group.id) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    Text(group.title.uppercased())
                        .font(.caption.weight(.semibold))
                    Text("\(group.projects.count)")
                        .font(.caption.monospacedDigit())
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !isCollapsed && layout == .grid {
                LazyVGrid(columns: CollectionLayout.gridColumns, spacing: 12) {
                    ForEach(group.projects) { item in
                        CortexProjectTile(project: item, isMapped: mappedIDs.contains(item.id)) {
                            selectedProjectID = item.id
                        }
                    }
                }
            } else if !isCollapsed {
                VStack(spacing: 0) {
                    ForEach(Array(group.projects.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().padding(.leading, 46) }
                        CortexProjectRow(project: item, isMapped: mappedIDs.contains(item.id)) {
                            selectedProjectID = item.id
                        }
                    }
                }
                .padding(.vertical, 4)
                .projectSurface(cornerRadius: 14)
            }
        }
    }

    /// Grouped by the folder above each project (Work/Pixeld, Personal, …): Work first, then Personal.
    /// Within a group, mapped projects lead because they have a synapse map to explore.
    private var visibleGroups: [CortexGroup] {
        let filtered = projects.filter { item in
            scope.matches(item, isMapped: mappedIDs.contains(item.id))
                && (searchText.isEmpty
                    || item.name.localizedCaseInsensitiveContains(searchText)
                    || item.route.projectPath.localizedCaseInsensitiveContains(searchText))
        }
        return Dictionary(grouping: filtered) { CortexGroup.key(for: $0.route.projectPath) }
            .map { key, items in
                CortexGroup(id: key, projects: items.sorted { lhs, rhs in
                    let lhsMapped = mappedIDs.contains(lhs.id), rhsMapped = mappedIDs.contains(rhs.id)
                    if lhsMapped != rhsMapped { return lhsMapped }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                })
            }
            .sorted { lhs, rhs in
                let lhsWork = lhs.id.hasPrefix("Work"), rhsWork = rhs.id.hasPrefix("Work")
                if lhsWork != rhsWork { return lhsWork }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
    }

    private func count(for scope: CortexScope) -> Int {
        projects.filter { scope.matches($0, isMapped: mappedIDs.contains($0.id)) }.count
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

    // MARK: Vault health

    private var vaultIsStale: Bool {
        health.map { Date.now.timeIntervalSince($0.checkedAt) > 86_400 } ?? false
    }

    private var vaultIssues: [VaultHealth.Issue] {
        health?.issues.filter { $0.level != "info" } ?? []
    }

    /// The doctor's verdict as one capsule; its issues and route problems open in a popover.
    private var vaultCapsule: some View {
        let errors = health?.errors ?? 0
        let warnings = (health?.warnings ?? 0) + routeIssues.count
        let (title, image, tint): (String, String, Color) =
            if health == nil && routeIssues.isEmpty {
                ("No vault report", "questionmark.circle", .secondary)
            } else if errors > 0 {
                ("\(errors) vault error\(errors == 1 ? "" : "s")", "xmark.octagon.fill", .red)
            } else if warnings > 0 {
                ("\(warnings) vault warning\(warnings == 1 ? "" : "s")", "exclamationmark.triangle.fill", .orange)
            } else if vaultIsStale {
                ("Vault report is stale", "clock.badge.exclamationmark", .orange)
            } else {
                ("Vault healthy", "checkmark.seal.fill", .green)
            }
        return Button { showingVaultIssues = true } label: {
            Label(title, systemImage: image)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingVaultIssues, arrowEdge: .bottom) { vaultPopover }
    }

    private var vaultPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let health {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vault health").font(.headline)
                    Text("\(health.errors) errors · \(health.warnings) warnings · checked \(health.checkedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if vaultIsStale {
                    Text("This report is over a day old. Check that the vault-maintenance job is running.")
                        .font(.caption).foregroundStyle(.orange)
                }
                ForEach(vaultIssues, id: \.self) { issue in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: issue.level == "error" ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.level == "error" ? .red : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(issue.check).font(.caption.weight(.semibold))
                            Text(issue.message).font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } else {
                Text("No vault health report was found. The vault doctor writes ICM/health.json.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !routeIssues.isEmpty {
                Divider()
                Label("ICM routes need attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                ForEach(routeIssues, id: \.self) { issue in
                    Text(issue).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Update ICM/routes.json. Other projects remain available.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if health != nil {
                HStack {
                    Spacer()
                    Button("Open Report") {
                        NSWorkspace.shared.open(vaultURL.appendingPathComponent(VaultHealth.reportPath))
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    /// The vault scan (icm.py) and file reads run off the main thread; a large vault
    /// previously froze the UI on appear and every 30 seconds.
    private func reload() {
        guard !isReloading else { return }
        isReloading = true
        let vault = vaultURL
        Task {
            let (result, latestHealth) = await Task.detached(priority: .userInitiated) {
                let result = Result { () throws -> (ConnectionsWorkspace, Set<String>) in
                    let workspace = try ConnectionsService.workspace(in: vault)
                    let mapped = workspace.projects
                        .filter { FileManager.default.fileExists(atPath: $0.graphURL.path) }
                        .map(\.id)
                    return (workspace, Set(mapped))
                }
                return (result, ConnectionsService.health(in: vault))
            }.value
            isReloading = false
            switch result {
            case let .success((workspace, mapped)):
                projects = workspace.projects
                mappedIDs = mapped
                routeIssues = workspace.routeIssues
                health = latestHealth
                if !projects.contains(where: { $0.id == selectedProjectID }) { selectedProjectID = nil }
                selectedFile = nil
                searchResults = []
                isSearching = false
                errorMessage = nil
            case let .failure(error):
                projects = []
                routeIssues = []
                health = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func runSearch(in project: ConnectionProject) {
        let query = query
        isSearching = true
        Task {
            searchResults = await Task.detached(priority: .userInitiated) {
                ConnectionsService.search(query, in: project)
            }.value
        }
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

// MARK: - Overview parts

enum CortexScope: String, CaseIterable, Identifiable {
    case all, work, personal, mapped, unmapped

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .work: "Work"
        case .personal: "Personal"
        case .mapped: "Mapped"
        case .unmapped: "No map"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .work: "briefcase"
        case .personal: "person"
        case .mapped: "point.3.connected.trianglepath.dotted"
        case .unmapped: "circle.dashed"
        }
    }

    func matches(_ project: ConnectionProject, isMapped: Bool) -> Bool {
        switch self {
        case .all: true
        case .work: project.route.projectPath.hasPrefix("Work/")
        case .personal: project.route.projectPath.hasPrefix("Personal/")
        case .mapped: isMapped
        case .unmapped: !isMapped
        }
    }
}

struct CortexGroup: Identifiable {
    /// The folder path above the project, e.g. "Work/Pixeld".
    let id: String
    let projects: [ConnectionProject]

    var title: String { id.replacingOccurrences(of: "/", with: " · ") }

    static func key(for projectPath: String) -> String {
        let parts = projectPath.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : "Other"
    }
}

private struct CortexScopeChip: View {
    let scope: CortexScope
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: scope.systemImage).font(.caption)
                Text(scope.title).font(.subheadline.weight(isSelected ? .semibold : .regular))
                Text("\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background((isSelected ? Color.cyan : Color.secondary).opacity(0.18), in: Capsule())
            }
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(isSelected ? Color.cyan : Color.primary)
            .background(
                Capsule().fill(isSelected ? Color.cyan.opacity(0.14) : Color.white.opacity(isHovering ? 0.07 : 0.035))
            )
            .overlay(Capsule().stroke(isSelected ? Color.cyan.opacity(0.45) : Color.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

/// One project as a single line. A click anywhere opens its source tree and synapse map.
private struct CortexProjectRow: View {
    let project: ConnectionProject
    let isMapped: Bool
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: isMapped ? "point.3.connected.trianglepath.dotted" : "circle.dashed")
                    .font(.body)
                    .foregroundStyle(isMapped ? Color.cyan : Color.secondary.opacity(0.6))
                    .frame(width: 22)
                Text(project.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 12)
                if project.isRegistered {
                    badge("ICM route", tint: .purple)
                }
                if isMapped {
                    badge("Mapped", tint: .cyan)
                } else {
                    Text("No map").font(.caption).foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0.35)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.white.opacity(isHovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(project.route.projectPath)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(tint.opacity(0.13), in: Capsule())
    }
}

/// One project as a grid tile; a click opens it, as a row does.
private struct CortexProjectTile: View {
    let project: ConnectionProject
    let isMapped: Bool
    let onOpen: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isMapped ? "point.3.connected.trianglepath.dotted" : "circle.dashed")
                        .font(.title3)
                        .foregroundStyle(isMapped ? Color.cyan : Color.secondary.opacity(0.6))
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.body.weight(.semibold))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(project.route.projectPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if isMapped {
                        badge("Mapped", tint: .cyan)
                    } else {
                        Text("No map").font(.caption).foregroundStyle(.tertiary)
                    }
                    if project.isRegistered {
                        badge("ICM route", tint: .purple)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .opacity(isHovering ? 1 : 0.35)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.78 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHovering ? Color.cyan.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(project.route.projectPath)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(tint.opacity(0.13), in: Capsule())
    }
}
