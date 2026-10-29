import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectItem.updatedAt, order: .reverse) private var projects: [ProjectItem]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @ObservedObject private var siteMonitor = SiteMonitor.shared

    @AppStorage("projects.sort") private var sortRawValue = ProjectSort.attention.rawValue
    @State private var scope = ProjectScope.active
    @State private var searchText = ""
    @State private var showingNewProject = false
    @State private var editingProject: ProjectItem?
    @State private var selectedProject: ProjectItem?
    @State private var projectPendingDeletion: ProjectItem?
    @State private var deletionError: String?

    private var sort: ProjectSort { ProjectSort(rawValue: sortRawValue) ?? .attention }

    private var taskCounts: [UUID: ProjectTaskCounts] {
        var counts: [UUID: ProjectTaskCounts] = [:]
        for task in tasks {
            guard let projectID = task.projectID else { continue }
            counts[projectID, default: ProjectTaskCounts()].add(task)
        }
        return counts
    }

    private var siteProjects: [ProjectItem] { projects.filter { $0.hasWebsite && !$0.isArchived } }
    private var operationalProjects: [ProjectItem] { projects.filter { !$0.isArchived && $0.status != .completed } }

    var body: some View {
        Group {
            if let selectedProject {
                ProjectDetailView(
                    project: selectedProject,
                    tasks: tasks.filter { $0.projectID == selectedProject.id }
                ) {
                    self.selectedProject = nil
                }
            } else {
                overview
            }
        }
        .background(projectsBackground)
        .navigationTitle(selectedProject?.name ?? "Projects")
        .toolbar {
            if selectedProject == nil {
                Button { showingNewProject = true } label: {
                    Label("New project", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showingNewProject) { ProjectEditorSheet() }
        .sheet(item: $editingProject) { ProjectEditorSheet(project: $0) }
        .confirmationDialog(
            "Delete \(projectPendingDeletion?.name ?? "this project")?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                guard let projectPendingDeletion else { return }
                if selectedProject === projectPendingDeletion { selectedProject = nil }
                do {
                    try ProjectStore.delete(projectPendingDeletion, from: modelContext)
                } catch {
                    deletionError = error.localizedDescription
                }
                self.projectPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { projectPendingDeletion = nil }
        } message: {
            Text("This permanently removes the project from this Mac. Its tasks move to the inbox. This action cannot be undone.")
        }
        .alert("Project not deleted", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deletionError ?? "")
        }
        .onAppear { openRequestedProjectIfNeeded() }
        .onChange(of: appState.requestedProjectID) { _, _ in openRequestedProjectIfNeeded() }
    }

    private func openRequestedProjectIfNeeded() {
        guard let projectID = appState.requestedProjectID,
              let project = projects.first(where: { $0.id == projectID }) else { return }
        selectedProject = project
        appState.consumeProjectRequest(projectID)
    }

    private var projectsBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.012, green: 0.028, blue: 0.052), Color(nsColor: .windowBackgroundColor)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: Overview

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                statusRail
                listSection
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1_180)
            .frame(maxWidth: .infinity)
        }
        .searchable(text: $searchText, prompt: "Search projects, clients, or websites")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Operations")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let attention = count(for: .attention)
            if attention > 0 {
                Button { scope = .attention } label: {
                    Label("\(attention) need\(attention == 1 ? "s" : "") attention", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button { showingNewProject = true } label: {
                Label("New Project", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.cyan)
        }
    }

    private var headerSubtitle: String {
        let down = siteProjects.filter { siteMonitor.health(for: $0).state == .down }
        if down.count == 1 { return "\(down[0].name) is down. Everything else is holding." }
        if down.count > 1 { return "\(down.count) sites are down." }
        if projects.isEmpty { return "Client work, deadlines, and the websites behind them." }
        return "\(operationalProjects.count) active operation\(operationalProjects.count == 1 ? "" : "s") and the websites behind them."
    }

    private var statusRail: some View {
        let healths = siteProjects.map { siteMonitor.health(for: $0) }
        let up = healths.filter { $0.state == .up || $0.state == .slow }.count
        let down = healths.filter { $0.state == .down }.count
        let uptimes = healths.compactMap(\.uptime)
        let averageUptime = uptimes.isEmpty ? nil : uptimes.reduce(0, +) / Double(uptimes.count)
        let dueSoon = operationalProjects.filter { project in
            guard let dueDate = project.dueDate else { return false }
            return dueDate < Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        }.count

        return HStack(spacing: 0) {
            ProjectMetric(title: "Active", value: "\(operationalProjects.count)", tint: .primary)
            ProjectMetricDivider()
            ProjectMetric(title: "Waiting on client", value: "\(count(for: .waiting))", tint: count(for: .waiting) > 0 ? .orange : .secondary)
            ProjectMetricDivider()
            ProjectMetric(title: "Due within 7 days", value: "\(dueSoon)", tint: dueSoon > 0 ? .cyan : .secondary)
            ProjectMetricDivider()
            ProjectMetric(title: "Sites up", value: healths.isEmpty ? "—" : "\(up)/\(healths.count)", tint: healths.isEmpty ? .secondary : .green)
            ProjectMetricDivider()
            ProjectMetric(title: "Down", value: "\(down)", tint: down > 0 ? .red : .secondary)
            ProjectMetricDivider()
            VStack(alignment: .leading, spacing: 4) {
                Text(averageUptime.map(uptimeText) ?? "—")
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(averageUptime == nil ? Color.secondary : Color.green)
                Text(checkedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .help("Average 30-day uptime across your sites")
        }
        .padding(.vertical, 18)
        .projectSurface(cornerRadius: 16)
    }

    private var checkedText: String {
        if siteMonitor.isOffline { return "Checks paused · offline" }
        guard let lastPassAt = siteMonitor.lastPassAt else { return "30-day uptime" }
        return "Uptime · checked \(lastPassAt.formatted(.relative(presentation: .named)))"
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(ProjectScope.allCases) { item in
                    ProjectScopeChip(scope: item, count: count(for: item), isSelected: scope == item) {
                        scope = item
                    }
                }
                Spacer(minLength: 12)
                Picker("Sort", selection: $sortRawValue) {
                    ForEach(ProjectSort.allCases) { sort in
                        Text(sort.title).tag(sort.rawValue)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .help("Sort projects")
                Button {
                    Task { await siteMonitor.checkAll() }
                } label: {
                    Label("Check all sites", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(siteMonitor.isChecking || siteProjects.isEmpty)
                .help("Check every website now")
            }

            if visibleProjects.isEmpty {
                emptyState
            } else {
                let counts = taskCounts
                LazyVStack(spacing: 12) {
                    ForEach(visibleProjects) { project in
                        ProjectCard(
                            project: project,
                            health: siteMonitor.health(for: project),
                            counts: counts[project.id] ?? ProjectTaskCounts(),
                            isChecking: siteMonitor.checkingIDs.contains(project.id),
                            onOpen: { selectedProject = project },
                            onEdit: { editingProject = project },
                            onCheckSite: { Task { await siteMonitor.check(project) } },
                            onDuplicate: { duplicate(project) },
                            onArchive: { archive(project) },
                            onDelete: { projectPendingDeletion = project }
                        )
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? scope.systemImage : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(emptyTitle).font(.headline)
            Text(emptyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if projects.isEmpty {
                Button("Create Project") { showingNewProject = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .projectSurface(cornerRadius: 16)
    }

    private var emptyTitle: String {
        if projects.isEmpty { return "No projects yet" }
        return searchText.isEmpty ? "Nothing here" : "No matching projects"
    }

    private var emptyMessage: String {
        if projects.isEmpty { return "Create your first project, give it a next action, and add its website." }
        guard searchText.isEmpty else { return "Try a broader search or another filter." }
        switch scope {
        case .active: return "No active operations. The board is clear."
        case .attention: return "Every site is up and nothing is overdue."
        case .waiting: return "No client is holding anything up."
        case .completed: return "Completed projects will collect here."
        case .archived: return "Archived projects will collect here."
        }
    }

    // MARK: Filtering and sorting

    private var visibleProjects: [ProjectItem] {
        let counts = taskCounts
        let matching = projects.filter { project in
            guard matches(project, scope: scope, counts: counts) else { return false }
            guard !searchText.isEmpty else { return true }
            return project.name.localizedCaseInsensitiveContains(searchText)
                || project.client.localizedCaseInsensitiveContains(searchText)
                || project.type.localizedCaseInsensitiveContains(searchText)
                || project.monitoringWebsiteURL.localizedCaseInsensitiveContains(searchText)
                || project.tagsRawValue.localizedCaseInsensitiveContains(searchText)
        }
        return matching.sorted { lhs, rhs in
            switch sort {
            case .attention:
                let lhsAttention = needsAttention(lhs, counts: counts)
                let rhsAttention = needsAttention(rhs, counts: counts)
                if lhsAttention != rhsAttention { return lhsAttention }
                let lhsRank = siteMonitor.health(for: lhs).sortRank
                let rhsRank = siteMonitor.health(for: rhs).sortRank
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                if lhs.priority != rhs.priority { return lhs.priority.rank > rhs.priority.rank }
                return lhs.updatedAt > rhs.updatedAt
            case .updated:
                return lhs.updatedAt > rhs.updatedAt
            case .due:
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            case .name:
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }

    private func matches(_ project: ProjectItem, scope: ProjectScope, counts: [UUID: ProjectTaskCounts]) -> Bool {
        switch scope {
        case .active: !project.isArchived && project.status != .completed
        case .attention: !project.isArchived && needsAttention(project, counts: counts)
        case .waiting: !project.isArchived && project.status == .waitingOnClient
        case .completed: !project.isArchived && project.status == .completed
        case .archived: project.isArchived
        }
    }

    /// A site that is down or slow, a client holding things up, a missed deadline, or overdue tasks.
    private func needsAttention(_ project: ProjectItem, counts: [UUID: ProjectTaskCounts]) -> Bool {
        if siteMonitor.health(for: project).needsAttention { return true }
        guard project.status != .completed else { return false }
        if project.status == .waitingOnClient { return true }
        if let dueDate = project.dueDate, Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: .now) { return true }
        return (counts[project.id]?.overdue ?? 0) > 0
    }

    private func count(for scope: ProjectScope) -> Int {
        let counts = taskCounts
        return projects.count { matches($0, scope: scope, counts: counts) }
    }

    private func duplicate(_ project: ProjectItem) {
        let copy = project.duplicate()
        modelContext.insert(copy)
        try? modelContext.save()
        selectedProject = copy
    }

    private func archive(_ project: ProjectItem) {
        project.status = project.isArchived ? .active : .archived
        project.updatedAt = .now
        try? modelContext.save()
    }
}

private enum ProjectScope: String, CaseIterable, Identifiable {
    case active
    case attention
    case waiting
    case completed
    case archived

    var id: Self { self }

    var title: String {
        switch self {
        case .active: "Active"
        case .attention: "Needs attention"
        case .waiting: "Waiting on client"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }

    var systemImage: String {
        switch self {
        case .active: "square.stack.3d.up"
        case .attention: "exclamationmark.triangle"
        case .waiting: "hourglass"
        case .completed: "checkmark.circle"
        case .archived: "archivebox"
        }
    }
}

private enum ProjectSort: String, CaseIterable, Identifiable {
    case attention
    case updated
    case due
    case name

    var id: Self { self }

    var title: String {
        switch self {
        case .attention: "Needs attention first"
        case .updated: "Recently updated"
        case .due: "Due date"
        case .name: "Name"
        }
    }
}

private struct ProjectTaskCounts {
    var open = 0
    var completed = 0
    var overdue = 0

    var total: Int { open + completed }

    mutating func add(_ task: TaskItem) {
        if task.isCompleted {
            completed += 1
        } else {
            open += 1
            if (task.dueDate ?? .distantFuture) < .now { overdue += 1 }
        }
    }
}

// MARK: - Overview pieces

private struct ProjectScopeChip: View {
    let scope: ProjectScope
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

/// One project in the list. A single click anywhere opens it.
private struct ProjectCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectItem
    let health: SiteHealth
    let counts: ProjectTaskCounts
    let isChecking: Bool
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onCheckSite: () -> Void
    let onDuplicate: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SiteStatusIcon(health: health, isChecking: isChecking)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(project.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                    if !project.client.isEmpty {
                        Text(project.client)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if !project.nextAction.isEmpty {
                    Label(project.nextAction, systemImage: "arrow.turn.down.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ProjectMetaChips(project: project, counts: counts)
                if project.mode == .fixed && counts.total > 0 {
                    ProgressView(value: Double(counts.completed), total: Double(counts.total))
                        .tint(.cyan)
                        .controlSize(.small)
                        .frame(maxWidth: 260)
                }
            }

            Spacer(minLength: 16)

            if project.hasWebsite {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(health.detail)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(health.colour)
                        .lineLimit(1)
                    Text(websiteHost(project.monitoringWebsiteURL))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let uptime = health.uptime {
                        Text("\(uptimeText(uptime)) · 30 days")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 140, alignment: .trailing)
            }

            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Menu {
                    Button("Open", systemImage: "arrow.up.right.square", action: onOpen)
                    Button("Edit…", systemImage: "pencil", action: onEdit)
                    Picker("Status", selection: statusBinding) {
                        ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) }
                    }
                    if project.hasWebsite {
                        Divider()
                        Button("Check Site Now", systemImage: "arrow.clockwise", action: onCheckSite)
                        if let url = URL(string: project.monitoringWebsiteURL) {
                            Link(destination: url) { Label("Open Website", systemImage: "safari") }
                        }
                    }
                    Divider()
                    Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    Button(
                        project.isArchived ? "Restore" : "Archive",
                        systemImage: project.isArchived ? "tray.and.arrow.up" : "archivebox",
                        action: onArchive
                    )
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
            }
            .opacity(isHovering ? 1 : 0.75)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.78 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColour, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            // Priority accent along the card's left edge, as on task cards.
            RoundedRectangle(cornerRadius: 2)
                .fill(project.priority.tint)
                .frame(width: 3)
                .padding(.vertical, 14)
        }
        .opacity(project.isArchived ? 0.72 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // Archiving from the Active list removes the card while the pointer is still on it.
        .onDisappear { if isHovering { NSCursor.pop() } }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Click to open")
        .contextMenu {
            Button("Open", systemImage: "arrow.up.right.square", action: onOpen)
            Button("Edit…", systemImage: "pencil", action: onEdit)
            if project.hasWebsite {
                Button("Check Site Now", systemImage: "arrow.clockwise", action: onCheckSite)
            }
            Divider()
            Button("Delete Project", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var borderColour: Color {
        if health.state == .down { return Color.red.opacity(isHovering ? 0.65 : 0.45) }
        return isHovering ? Color.cyan.opacity(0.45) : Color.white.opacity(0.07)
    }

    private var statusBinding: Binding<ProjectStatus> {
        Binding(
            get: { project.status },
            set: { newStatus in
                project.status = newStatus
                project.updatedAt = .now
                try? modelContext.save()
            }
        )
    }
}

/// Status, priority, due date, and task progress as small chips.
private struct ProjectMetaChips: View {
    let project: ProjectItem
    let counts: ProjectTaskCounts

    var body: some View {
        HStack(spacing: 8) {
            ProjectChip(text: project.status.title, systemImage: project.status.systemImage, tint: project.status.tint)
            ProjectPriorityChip(priority: project.priority)
            if let dueDate = project.dueDate {
                let due = DueDescription(date: dueDate, status: project.status)
                ProjectChip(text: due.text, systemImage: due.systemImage, tint: due.tint)
            }
            if counts.total > 0 {
                ProjectChip(
                    text: project.mode == .fixed ? "\(counts.completed) of \(counts.total) tasks" : "\(counts.open) open task\(counts.open == 1 ? "" : "s")",
                    systemImage: "checklist",
                    tint: .secondary
                )
            }
            if counts.overdue > 0 {
                ProjectChip(text: "\(counts.overdue) overdue", systemImage: "clock.badge.exclamationmark", tint: .red)
            }
            if let waitingDays = project.waitingDays() {
                ProjectChip(text: "Waiting \(waitingDays) day\(waitingDays == 1 ? "" : "s")", systemImage: "hourglass", tint: .orange)
            }
            if project.mode == .ongoing {
                ProjectChip(text: "Ongoing", systemImage: "repeat", tint: .secondary)
            }
        }
    }
}

private struct ProjectChip: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Color.white.opacity(0.05), in: Capsule())
    }
}

private struct ProjectPriorityChip: View {
    let priority: ProjectPriority

    var body: some View {
        Text(priority.title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(priority.tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(priority.tint.opacity(0.14), in: Capsule())
    }
}

private struct SiteStatusIcon: View {
    let health: SiteHealth
    let isChecking: Bool
    var size: CGFloat = 22

    var body: some View {
        Group {
            if isChecking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: health.systemImage)
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(health.colour)
                    .opacity(health.state == .noWebsite ? 0.45 : 1)
            }
        }
        .frame(width: size + 6, height: size + 6)
        .help(health.state == .noWebsite ? "No website to check" : "Website \(health.label.lowercased())")
    }
}

struct ProjectMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(tint).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

struct ProjectMetricDivider: View {
    var body: some View { Divider().frame(height: 38) }
}

// MARK: - Detail

private struct ProjectDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var siteMonitor = SiteMonitor.shared
    @Bindable var project: ProjectItem
    let tasks: [TaskItem]
    let onBack: () -> Void

    @State private var savedAt: Date?
    @State private var repositorySnapshot: RepositorySnapshot?
    @State private var repositoryError: String?
    @State private var isRefreshingRepository = false
    @State private var showingRepositoryPicker = false
    @State private var showingNewTask = false
    @State private var taskBeingEdited: TaskItem?

    private var snapshot: ProjectSnapshot { ProjectSnapshot(project: project) }
    private var health: SiteHealth { siteMonitor.health(for: project) }
    private var completedTaskCount: Int { tasks.filter(\.isCompleted).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button(action: onBack) {
                    Label("Operations", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                header
                metricsRail

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        WebsitePanel(siteMonitor: siteMonitor, project: project)
                        tasksPanel
                        if project.mode == .ongoing { repositoryPanel }
                        ProjectPanel(title: "Description", systemImage: "text.alignleft") {
                            TextField("Project scope, context and goals", text: $project.summary, axis: .vertical)
                                .lineLimit(4...10)
                                .textFieldStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 20) {
                        ProjectPanel(title: "Next action", systemImage: "arrow.turn.down.right") {
                            TextField("What should happen next?", text: $project.nextAction, axis: .vertical)
                                .lineLimit(2...6)
                                .textFieldStyle(.plain)
                        }
                        detailsPanel
                    }
                    .frame(width: 320)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 1_180)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: snapshot) { _, _ in persistChanges() }
        .fileImporter(
            isPresented: $showingRepositoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            connectRepository(from: result)
        }
        .task(id: project.repositoryBookmarkData) {
            await refreshRepository()
        }
        .sheet(isPresented: $showingNewTask) { TaskEditorView(projectID: project.id) }
        .sheet(item: $taskBeingEdited) { TaskEditorView(editing: $0) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Project name", text: $project.name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    TextField("Client", text: $project.client)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let savedAt {
                    Label("Saved", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Last saved \(savedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
            HStack(spacing: 12) {
                Picker("Status", selection: $project.status) {
                    ForEach(ProjectStatus.allCases) { Text($0.title).tag($0) }
                }
                Picker("Priority", selection: $project.priority) {
                    ForEach(ProjectPriority.allCases) { Text($0.title).tag($0) }
                }
                Picker("Mode", selection: $project.mode) {
                    ForEach(ProjectMode.allCases) { Text($0.title).tag($0) }
                }
            }
            .fixedSize()
        }
    }

    private var metricsRail: some View {
        HStack(spacing: 0) {
            if project.mode == .ongoing {
                ProjectMetric(
                    title: "Repository",
                    value: RepositoryHealth.evaluate(status: project.status, dueDate: project.dueDate, snapshot: repositorySnapshot).title,
                    tint: .primary
                )
                ProjectMetricDivider()
                ProjectMetric(title: "Commits · 30 days", value: repositorySnapshot.map { "\($0.commitsInLast30Days)" } ?? "—", tint: .primary)
            } else {
                ProjectMetric(title: "Progress", value: taskProgress.formatted(.percent.precision(.fractionLength(0))), tint: .cyan)
                ProjectMetricDivider()
                ProjectMetric(title: "Tasks done", value: "\(completedTaskCount)/\(tasks.count)", tint: .primary)
            }
            ProjectMetricDivider()
            if let dueDate = project.dueDate {
                let due = DueDescription(date: dueDate, status: project.status)
                ProjectMetric(title: "Deadline", value: due.shortText, tint: due.tint == .secondary ? .primary : due.tint)
            } else {
                ProjectMetric(title: "Deadline", value: "None", tint: .secondary)
            }
            ProjectMetricDivider()
            ProjectMetric(title: "Website", value: health.label, tint: project.hasWebsite ? health.colour : .secondary)
            ProjectMetricDivider()
            ProjectMetric(title: "Uptime · 30 days", value: health.uptime.map(uptimeText) ?? "—", tint: health.uptime == nil ? .secondary : .green)
        }
        .padding(.vertical, 18)
        .projectSurface(cornerRadius: 16)
    }

    private var taskProgress: Double {
        guard !tasks.isEmpty else { return project.progress }
        return Double(completedTaskCount) / Double(tasks.count)
    }

    private var tasksPanel: some View {
        ProjectPanel(title: "Tasks", systemImage: "checklist") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tasks.isEmpty ? "No linked tasks yet" : "\(completedTaskCount) of \(tasks.count) complete")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Task", systemImage: "plus") { showingNewTask = true }
                }
                let ordered = TaskQueueEngine.sorted(tasks.filter { !$0.isCompleted }) + tasks.filter(\.isCompleted)
                ForEach(ordered.prefix(10)) { task in
                    ProjectTaskRow(task: task) { taskBeingEdited = task }
                }
                if tasks.count > 10 {
                    Button("Show all \(tasks.count) tasks in Tasks") { appState.selection = .tasks }
                        .buttonStyle(.plain)
                        .foregroundStyle(.cyan)
                }
            }
        }
    }

    private var detailsPanel: some View {
        ProjectPanel(title: "Details", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("Type") {
                    TextField("Website Build", text: $project.type)
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Mode", selection: $project.mode) {
                        ForEach(ProjectMode.allCases) { Text($0.title).tag($0) }
                    }
                    Text(project.mode.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                OptionalDateEditor(label: "Start date", date: $project.startDate)
                OptionalDateEditor(label: "Due date", date: $project.dueDate)
                LabeledContent("Tags") {
                    TextField("WordPress, Retainer", text: $project.tagsRawValue)
                        .multilineTextAlignment(.trailing)
                }
                Divider()
                Text("Created \(project.createdAt.formatted(date: .abbreviated, time: .omitted)) · updated \(project.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var repositoryPanel: some View {
        ProjectPanel(title: "Local repository", systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.hasRepository ? project.repositoryPath : "No repository connected")
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("Read-only local Git metadata. JARVIS never modifies repository files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if project.hasRepository {
                        Button("Disconnect", role: .destructive) { disconnectRepository() }
                    }
                    Button(project.hasRepository ? "Choose Another…" : "Connect Repository…") {
                        showingRepositoryPicker = true
                    }
                }

                if isRefreshingRepository {
                    ProgressView("Reading repository…")
                        .controlSize(.small)
                } else if let repositoryError {
                    Label(repositoryError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if let repositorySnapshot {
                    Divider()
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            Text("Health").foregroundStyle(.secondary)
                            RepositoryHealthBadge(
                                health: RepositoryHealth.evaluate(
                                    status: project.status,
                                    dueDate: project.dueDate,
                                    snapshot: repositorySnapshot
                                )
                            )
                        }
                        GridRow {
                            Text("Branch").foregroundStyle(.secondary)
                            Text(repositorySnapshot.branch).textSelection(.enabled)
                        }
                        GridRow {
                            Text("Working tree").foregroundStyle(.secondary)
                            Text(repositorySnapshot.dirtyFileCount == 0
                                 ? "Clean"
                                 : "\(repositorySnapshot.dirtyFileCount) changed file\(repositorySnapshot.dirtyFileCount == 1 ? "" : "s")")
                        }
                        GridRow {
                            Text("Last commit").foregroundStyle(.secondary)
                            HStack {
                                Text(repositorySnapshot.lastCommitHash).monospaced()
                                Text(repositorySnapshot.lastCommitMessage).lineLimit(1)
                                if let date = repositorySnapshot.lastCommitDate {
                                    Text(date, style: .relative).foregroundStyle(.secondary)
                                }
                            }
                        }
                        GridRow {
                            Text("Recent activity").foregroundStyle(.secondary)
                            Text("\(repositorySnapshot.commitsInLast30Days) commits in the last 30 days")
                        }
                        if repositorySnapshot.aheadCount > 0 || repositorySnapshot.behindCount > 0 {
                            GridRow {
                                Text("Remote state").foregroundStyle(.secondary)
                                Text("Ahead \(repositorySnapshot.aheadCount) · Behind \(repositorySnapshot.behindCount)")
                            }
                        }
                    }

                    Button("Refresh Repository", systemImage: "arrow.clockwise") {
                        Task { await refreshRepository() }
                    }
                }
            }
        }
    }

    private func persistChanges() {
        project.updatedAt = .now
        try? modelContext.save()
        savedAt = .now
    }

    private func connectRepository(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            project.repositoryBookmarkData = try GitRepositoryService.bookmark(for: url)
            project.repositoryPath = url.path
            project.updatedAt = .now
            try modelContext.save()
            Task { await refreshRepository() }
        } catch {
            repositoryError = error.localizedDescription
        }
    }

    private func disconnectRepository() {
        project.repositoryBookmarkData = nil
        project.repositoryPath = ""
        repositorySnapshot = nil
        repositoryError = nil
        project.updatedAt = .now
        try? modelContext.save()
    }

    private func refreshRepository() async {
        guard let bookmark = project.repositoryBookmarkData else {
            repositorySnapshot = nil
            repositoryError = nil
            return
        }
        isRefreshingRepository = true
        defer { isRefreshingRepository = false }
        do {
            let inspection = try await GitRepositoryService.inspect(bookmarkData: bookmark)
            repositorySnapshot = inspection.snapshot
            repositoryError = nil
            if let refreshed = inspection.refreshedBookmarkData {
                project.repositoryBookmarkData = refreshed
                try? modelContext.save()
            }
        } catch {
            repositorySnapshot = nil
            repositoryError = error.localizedDescription
        }
    }
}

private struct ProjectTaskRow: View {
    @Bindable var task: TaskItem
    let onEdit: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Button {
                TaskStore.setCompleted(task, !task.isCompleted)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Reopen" : "Mark complete")
            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(1)
            if task.isBlocked && !task.isCompleted {
                Label("Blocked", systemImage: "hand.raised.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(task.blockedReason)
            }
            Spacer()
            if let dueDate = task.dueDate {
                Text(dueDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(!task.isCompleted && dueDate < .now ? .red : .secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(isHovering ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { isHovering = $0 }
        .help("Click to edit")
    }
}

/// The project's website: its address, live status, 30-day history, and recent outages.
private struct WebsitePanel: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var siteMonitor: SiteMonitor
    @Bindable var project: ProjectItem
    @State private var draftURL = ""
    @State private var isEditing = false
    @State private var errorText: String?

    private var health: SiteHealth { siteMonitor.health(for: project) }
    private var record: SiteRecord? { siteMonitor.record(for: project) }
    private var isChecking: Bool { siteMonitor.checkingIDs.contains(project.id) }

    var body: some View {
        ProjectPanel(title: "Website", systemImage: "globe") {
            if !project.hasWebsite || isEditing {
                editor
            } else {
                status
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(project.hasWebsite
                 ? "Change the address JARVIS checks. The site's history starts again."
                 : "Add the site's address and JARVIS checks it every 5 minutes from this Mac. Nothing to install, nothing to pay for.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                TextField("example.com", text: $draftURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                if isEditing {
                    Button("Cancel") {
                        isEditing = false
                        errorText = nil
                    }
                }
                Button(project.hasWebsite ? "Save" : "Start Checking", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .disabled(draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let errorText {
                Text(errorText).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                SiteStatusIcon(health: health, isChecking: isChecking, size: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(health.detail)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(health.colour)
                    if let url = URL(string: project.monitoringWebsiteURL) {
                        Link(websiteHost(project.monitoringWebsiteURL), destination: url)
                            .font(.callout)
                    }
                }
                Spacer()
                Button {
                    Task { await siteMonitor.check(project) }
                } label: {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
                .disabled(isChecking)
                Menu {
                    Button("Change Address…", systemImage: "pencil") {
                        draftURL = project.monitoringWebsiteURL
                        isEditing = true
                    }
                    Button("Stop Checking", systemImage: "xmark.circle", role: .destructive) { remove() }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if let check = health.lastCheck, check.outcome == .failed, let error = check.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(health.colour)
            }

            HStack(spacing: 0) {
                stat("Last check", health.lastCheck.map { $0.checkedAt.formatted(.relative(presentation: .named)) } ?? "Pending")
                stat("HTTP", health.lastCheck?.statusCode.map(String.init) ?? "—")
                stat("Response", health.lastCheck?.responseMilliseconds.map { "\($0) ms" } ?? "—")
                stat("Uptime · 30 days", health.uptime.map(uptimeText) ?? "—")
            }

            UptimeStrip(days: record?.days ?? [])

            if let outages = record?.outages, !outages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("RECENT OUTAGES")
                        .font(.caption2.weight(.bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    ForEach(outages.suffix(5).reversed()) { outage in
                        HStack {
                            Circle()
                                .fill(outage.end == nil ? Color.red : Color.secondary.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text(outage.start.formatted(date: .abbreviated, time: .shortened))
                            Text(outage.reason).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text(outage.end.map { "Lasted \(SiteHealth.duration($0.timeIntervalSince(outage.start)))" } ?? "Ongoing")
                                .foregroundStyle(outage.end == nil ? .red : .secondary)
                        }
                        .font(.callout)
                    }
                }
            }

            Text("Checked every 5 minutes from this Mac while JARVIS is open. A site counts as down after two failed checks in a row.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline.monospacedDigit()).lineLimit(1)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        guard let url = SiteChecker.normalizedURL(from: draftURL) else {
            errorText = "Enter a web address such as example.com."
            return
        }
        project.monitoringWebsiteURL = url.absoluteString
        project.updatedAt = .now
        try? modelContext.save()
        isEditing = false
        errorText = nil
        draftURL = ""
        Task { await siteMonitor.check(project) }
    }

    private func remove() {
        project.monitoringWebsiteURL = ""
        project.updatedAt = .now
        try? modelContext.save()
        Task { await siteMonitor.checkAll() }
    }
}

/// The last 30 days, one bar per day: green when every check passed, amber for a few failures, red for more.
private struct UptimeStrip: View {
    let days: [SiteRecord.Day]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                ForEach(0..<SiteRecord.historyDays, id: \.self) { index in
                    let date = calendar.date(byAdding: .day, value: index - (SiteRecord.historyDays - 1), to: today) ?? today
                    let day = days.first { calendar.isDate($0.day, inSameDayAs: date) }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colour(for: day))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .help(helpText(date: date, day: day))
                }
            }
            HStack {
                Text("30 days ago")
                Spacer()
                Text("Today")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func colour(for day: SiteRecord.Day?) -> Color {
        guard let day, day.checks > 0 else { return Color.white.opacity(0.08) }
        if day.failures == 0 { return Color(red: 0.24, green: 0.81, blue: 0.56) }
        return Double(day.failures) / Double(day.checks) < 0.05
            ? Color(red: 0.96, green: 0.65, blue: 0.14)
            : Color(red: 0.94, green: 0.33, blue: 0.31)
    }

    private func helpText(date: Date, day: SiteRecord.Day?) -> String {
        let label = date.formatted(.dateTime.day().month(.abbreviated))
        guard let day, day.checks > 0 else { return "\(label) · no checks" }
        let uptime = Double(day.checks - day.failures) / Double(day.checks)
        return "\(label) · \(uptimeText(uptime)) up · \(day.checks) checks"
    }
}

private struct ProjectPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(.cyan)
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .projectSurface(cornerRadius: 16)
    }
}

// MARK: - Editor

private struct ProjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let project: ProjectItem?
    @State private var draft: ProjectDraft

    init(project: ProjectItem? = nil) {
        self.project = project
        _draft = State(initialValue: ProjectDraft(project: project))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Project name", text: $draft.name)
                    TextField("Client", text: $draft.client)
                    TextField("Type", text: $draft.type, prompt: Text("Website Build"))
                    Picker("Status", selection: $draft.status) {
                        ForEach(ProjectStatus.allCases) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    Picker("Priority", selection: $draft.priority) {
                        ForEach(ProjectPriority.allCases) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                    Picker("Project mode", selection: $draft.mode) {
                        ForEach(ProjectMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                Section {
                    TextField("Website", text: $draft.websiteURL, prompt: Text("example.com"))
                } header: {
                    Text("Website")
                } footer: {
                    Text(draft.hasInvalidWebsite
                         ? "Enter a web address such as example.com, or leave it empty."
                         : "JARVIS checks it every 5 minutes and tells you if it goes down.")
                        .foregroundStyle(draft.hasInvalidWebsite ? .red : .secondary)
                }

                Section("Schedule") {
                    OptionalDateEditor(label: "Start date", date: $draft.startDate)
                    OptionalDateEditor(label: "Due date", date: $draft.dueDate)
                }

                Section("Details") {
                    TextField("Description", text: $draft.summary, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Tags", text: $draft.tagsText, prompt: Text("WordPress, Retainer"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(project == nil ? "New Project" : "Edit Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(project == nil ? "Create" : "Done") {
                        save()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.trimmedName.isEmpty || draft.hasInvalidWebsite)
                }
            }
        }
        .frame(width: 560, height: 680)
    }

    private func save() {
        let saved: ProjectItem
        let websiteChanged: Bool
        if let project {
            websiteChanged = project.monitoringWebsiteURL != draft.normalizedWebsite
            draft.apply(to: project)
            saved = project
        } else {
            saved = draft.makeProject()
            websiteChanged = saved.hasWebsite
            modelContext.insert(saved)
        }
        try? modelContext.save()
        if websiteChanged { Task { await SiteMonitor.shared.checkAll() } }
    }
}

private struct ProjectDraft {
    var name = ""
    var client = ""
    var type = ""
    var status = ProjectStatus.active
    var priority = ProjectPriority.medium
    var mode = ProjectMode.fixed
    var startDate: Date?
    var dueDate: Date?
    var summary = ""
    var tagsText = ""
    var websiteURL = ""

    init(project: ProjectItem? = nil) {
        guard let project else { return }
        name = project.name
        client = project.client
        type = project.type
        status = project.status
        priority = project.priority
        mode = project.mode
        startDate = project.startDate
        dueDate = project.dueDate
        summary = project.summary
        tagsText = project.tagsRawValue
        websiteURL = project.monitoringWebsiteURL
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var normalizedWebsite: String {
        SiteChecker.normalizedURL(from: websiteURL)?.absoluteString ?? ""
    }

    var hasInvalidWebsite: Bool {
        !websiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && SiteChecker.normalizedURL(from: websiteURL) == nil
    }

    func makeProject() -> ProjectItem {
        let project = ProjectItem(
            name: trimmedName,
            client: client.trimmingCharacters(in: .whitespacesAndNewlines),
            type: type.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            status: status,
            priority: priority,
            mode: mode,
            startDate: startDate,
            dueDate: dueDate,
            tags: tagsText.split(separator: ",").map(String.init)
        )
        project.monitoringWebsiteURL = normalizedWebsite
        return project
    }

    func apply(to project: ProjectItem) {
        project.name = trimmedName
        project.client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        project.type = type.trimmingCharacters(in: .whitespacesAndNewlines)
        project.summary = summary
        project.status = status
        project.priority = priority
        project.mode = mode
        project.startDate = startDate
        project.dueDate = dueDate
        project.tagsRawValue = tagsText
        project.monitoringWebsiteURL = normalizedWebsite
        project.updatedAt = .now
    }
}

private struct ProjectSnapshot: Equatable {
    let name: String
    let client: String
    let type: String
    let status: String
    let priority: String
    let mode: String
    let startDate: Date?
    let dueDate: Date?
    let summary: String
    let nextAction: String
    let tags: String
    let repositoryPath: String
    let repositoryBookmarkData: Data?
    let websiteURL: String

    init(project: ProjectItem) {
        name = project.name
        client = project.client
        type = project.type
        status = project.statusRawValue
        priority = project.priorityRawValue
        mode = project.modeRawValue
        startDate = project.startDate
        dueDate = project.dueDate
        summary = project.summary
        nextAction = project.nextAction
        tags = project.tagsRawValue
        repositoryPath = project.repositoryPath
        repositoryBookmarkData = project.repositoryBookmarkData
        websiteURL = project.monitoringWebsiteURL
    }
}

private struct OptionalDateEditor: View {
    let label: String
    @Binding var date: Date?

    var body: some View {
        LabeledContent(label) {
            HStack {
                Toggle("", isOn: Binding(
                    get: { date != nil },
                    set: { enabled in date = enabled ? (date ?? .now) : nil }
                ))
                .labelsHidden()
                if date != nil {
                    DatePicker(
                        "",
                        selection: Binding(get: { date ?? .now }, set: { date = $0 }),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                }
            }
        }
    }
}

private struct RepositoryHealthBadge: View {
    let health: RepositoryHealth

    private var color: Color {
        switch health {
        case .healthy: .green
        case .quiet: .yellow
        case .attention: .orange
        case .blocked: .red
        case .setupNeeded: .secondary
        }
    }

    private var systemImage: String {
        switch health {
        case .healthy: "checkmark.circle.fill"
        case .quiet: "moon.zzz.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        case .setupNeeded: "link.badge.plus"
        }
    }

    var body: some View {
        Label(health.title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Shared helpers

/// A project deadline as chip text: "Overdue · 8 Oct", "Due in 3 days", "Due 14 Nov".
private struct DueDescription {
    let text: String
    let shortText: String
    let systemImage: String
    let tint: Color

    init(date: Date, status: ProjectStatus, now: Date = .now, calendar: Calendar = .current) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        let formatted = date.formatted(.dateTime.day().month(.abbreviated))
        let finished = status == .completed || status == .archived
        shortText = formatted
        if finished {
            text = "Due \(formatted)"
            systemImage = "calendar"
            tint = .secondary
        } else if days < 0 {
            text = "Overdue · \(formatted)"
            systemImage = "exclamationmark.triangle.fill"
            tint = .red
        } else if days == 0 {
            text = "Due today"
            systemImage = "clock.fill"
            tint = .orange
        } else if days < 7 {
            text = "Due in \(days) day\(days == 1 ? "" : "s")"
            systemImage = "clock.fill"
            tint = .orange
        } else {
            text = "Due \(formatted)"
            systemImage = "calendar"
            tint = .secondary
        }
    }
}

private extension ProjectStatus {
    var tint: Color {
        switch self {
        case .notStarted, .archived: .secondary
        case .active: .cyan
        case .inReview: .purple
        case .onHold, .waitingOnClient: .orange
        case .completed: .green
        }
    }

    var systemImage: String {
        switch self {
        case .notStarted: "circle.dashed"
        case .active: "bolt.fill"
        case .inReview: "eye.fill"
        case .onHold: "pause.circle.fill"
        case .waitingOnClient: "hourglass"
        case .completed: "checkmark.circle.fill"
        case .archived: "archivebox.fill"
        }
    }
}

private extension ProjectPriority {
    var tint: Color {
        switch self {
        case .low: .secondary
        case .medium: .cyan
        case .high: .orange
        case .urgent: .red
        }
    }

    var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .urgent: 3
        }
    }
}

/// Rounds down, so a site with any failure never shows 100%.
private func uptimeText(_ uptime: Double) -> String {
    uptime >= 1 ? "100%" : (floor(uptime * 1_000) / 1_000).formatted(.percent.precision(.fractionLength(1)))
}

private func websiteHost(_ urlText: String) -> String {
    guard let url = URL(string: urlText), let host = url.host() else { return urlText }
    let path = url.path() == "/" ? "" : url.path()
    return host.replacingOccurrences(of: "www.", with: "", options: .anchored) + path
}

extension View {
    func projectSurface(cornerRadius: CGFloat, highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(highlighted ? 0.72 : 0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(highlighted ? Color.cyan.opacity(0.30) : Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}
