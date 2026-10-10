import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectItem.updatedAt, order: .reverse) private var projects: [ProjectItem]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @AppStorage("projects.showArchived") private var showArchived = false
    @AppStorage("monitoring.apiBaseURL") private var monitoringAPIBaseURL = MonitoringAPIService.defaultBaseURL
    @State private var showingNewProject = false
    @State private var editingProject: ProjectItem?
    @State private var selectedProject: ProjectItem?
    @State private var selectedDetailSection = ProjectDetailSection.overview
    @State private var projectPendingDeletion: ProjectItem?
    @State private var monitoringSites: [String: MonitoringSite] = [:]
    @State private var monitoringError: String?
    @State private var isRefreshingMonitoring = false
    @State private var needsAttentionOnly = false
    @State private var sortBySiteHealth = false

    private let monitoringService = MonitoringAPIService()
    private let monitoringCredentialStore = MonitoringAPICredentialStore()

    private var visibleProjects: [ProjectItem] {
        let filtered = projects.filter { project in
            guard showArchived || !project.isArchived else { return false }
            guard needsAttentionOnly else { return true }
            return MonitoringHealth.evaluate(site: site(for: project), connected: project.hasMonitoringSite).needsAttention
        }
        guard sortBySiteHealth else { return filtered }
        return filtered.sorted {
            let lhs = MonitoringHealth.evaluate(site: site(for: $0), connected: $0.hasMonitoringSite)
            let rhs = MonitoringHealth.evaluate(site: site(for: $1), connected: $1.hasMonitoringSite)
            if lhs.sortRank != rhs.sortRank { return lhs.sortRank < rhs.sortRank }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        Group {
            if let selectedProject {
                ProjectDetailView(
                    project: selectedProject,
                    selectedSection: $selectedDetailSection,
                    monitoringSite: site(for: selectedProject),
                    tasks: tasks.filter { $0.projectID == selectedProject.id },
                    monitoringError: monitoringError,
                    isRefreshingMonitoring: isRefreshingMonitoring,
                    onRefreshMonitoring: { Task { await refreshMonitoring() } }
                ) {
                    self.selectedProject = nil
                    selectedDetailSection = .overview
                }
            } else {
                projectGrid
            }
        }
        .navigationTitle(selectedProject == nil ? "Projects" : selectedProject?.name ?? "Project")
        .toolbar { projectToolbar }
        .sheet(isPresented: $showingNewProject) {
            ProjectEditorSheet()
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorSheet(project: project)
        }
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
                modelContext.delete(projectPendingDeletion)
                try? modelContext.save()
                self.projectPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { projectPendingDeletion = nil }
        } message: {
            Text("This permanently removes the project from this Mac. This action cannot be undone.")
        }
        .task {
            await refreshMonitoring()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard !Task.isCancelled else { break }
                await refreshMonitoring()
            }
        }
        .onAppear { openRequestedProjectIfNeeded() }
        .onChange(of: appState.requestedProjectID) { _, _ in openRequestedProjectIfNeeded() }
    }

    private func openRequestedProjectIfNeeded() {
        guard let projectID = appState.requestedProjectID,
              let project = projects.first(where: { $0.id == projectID }) else { return }
        selectedDetailSection = .overview
        selectedProject = project
        appState.consumeProjectRequest(projectID)
    }

    @ViewBuilder
    private var projectGrid: some View {
        if visibleProjects.isEmpty {
            ContentUnavailableView {
                Label(
                    projects.isEmpty ? "No projects yet" : "No active projects",
                    systemImage: "square.stack.3d.up"
                )
            } description: {
                Text(projects.isEmpty
                     ? "Create your first project and give it a clear next action."
                     : "Archived projects are currently hidden.")
            } actions: {
                if projects.isEmpty {
                    Button("Create Project") { showingNewProject = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                } else {
                    Button("Show Archived") { showArchived = true }
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    monitoringFleetHeader

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 480), spacing: 16)], spacing: 16) {
                        ForEach(visibleProjects) { project in
                            ProjectCard(
                                project: project,
                                monitoringSite: site(for: project),
                                tasks: tasks.filter { $0.projectID == project.id },
                                onOpen: {
                                    selectedDetailSection = .overview
                                    selectedProject = project
                                },
                                onOpenSecurity: {
                                    selectedDetailSection = .security
                                    selectedProject = project
                                },
                                onEdit: { editingProject = project },
                                onDuplicate: { duplicate(project) },
                                onArchive: { archive(project) },
                                onDelete: { projectPendingDeletion = project }
                            )
                        }
                    }
                }
                .padding(24)
            }
        }
    }

    private var monitoringFleetHeader: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(fleetSummaryColour)
                .frame(width: 9, height: 9)
            Text(fleetSummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let monitoringError {
                Label("Offline · cached project links shown", systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(monitoringError)
            }

            Spacer()

            Toggle("Needs attention", isOn: $needsAttentionOnly)
                .toggleStyle(.button)
                .buttonStyle(.bordered)

            Toggle("Sort: Site health", isOn: $sortBySiteHealth)
                .toggleStyle(.button)
                .buttonStyle(.bordered)

            Button {
                Task { await refreshMonitoring() }
            } label: {
                Label("Refresh monitoring", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .disabled(isRefreshingMonitoring)
            .help("Refresh monitoring data")
        }
        .controlSize(.small)
    }

    private var fleetSummaryText: String {
        let connectedProjects = projects.filter { $0.hasMonitoringSite }
        let health = connectedProjects.map { MonitoringHealth.evaluate(site: site(for: $0), connected: true) }
        let healthy = health.filter { $0.state == .healthy }.count
        let attention = health.filter { $0.state == .needsAttention || $0.state == .stale }.count
        let critical = health.filter { $0.state == .critical || $0.state == .down }.count
        let pending = health.filter { $0.state == .awaitingChecks }.count
        guard !connectedProjects.isEmpty else { return "No monitored sites connected" }
        var parts = ["\(connectedProjects.count) site\(connectedProjects.count == 1 ? "" : "s")", "\(healthy) healthy"]
        if attention > 0 { parts.append("\(attention) need attention") }
        if critical > 0 { parts.append("\(critical) critical") }
        if pending > 0 { parts.append("\(pending) awaiting checks") }
        return parts.joined(separator: " · ")
    }

    private var fleetSummaryColour: Color {
        let states = projects.filter(\.hasMonitoringSite).map { MonitoringHealth.evaluate(site: site(for: $0), connected: true).state }
        if states.contains(.down) || states.contains(.critical) { return .red }
        if states.contains(.needsAttention) || states.contains(.stale) { return .orange }
        if states.contains(.healthy) { return .green }
        return .secondary
    }

    @ToolbarContentBuilder
    private var projectToolbar: some ToolbarContent {
        if selectedProject == nil {
            ToolbarItemGroup {
                Menu {
                    Toggle("Show Archived", isOn: $showArchived)
                    Toggle("Needs Attention", isOn: $needsAttentionOnly)
                    Toggle("Sort by Site Health", isOn: $sortBySiteHealth)
                } label: {
                    Label("Project filters", systemImage: "line.3.horizontal.decrease.circle")
                }

                Button { showingNewProject = true } label: {
                    Label("New project", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
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

    private func site(for project: ProjectItem) -> MonitoringSite? {
        guard !project.monitoringSiteID.isEmpty else { return nil }
        return monitoringSites[project.monitoringSiteID]
    }

    @MainActor
    private func refreshMonitoring() async {
        guard !isRefreshingMonitoring else { return }
        guard let token = monitoringCredentialStore.read() else {
            monitoringError = "Add a monitoring read token in Settings."
            return
        }
        isRefreshingMonitoring = true
        defer { isRefreshingMonitoring = false }
        do {
            let summaries = try await monitoringService.sites(baseURLText: monitoringAPIBaseURL, readToken: token)
            var detailed: [String: MonitoringSite] = [:]
            try await withThrowingTaskGroup(of: MonitoringSite.self) { group in
                for summary in summaries {
                    group.addTask {
                        try await monitoringService.site(
                            baseURLText: monitoringAPIBaseURL,
                            readToken: token,
                            siteID: summary.id
                        )
                    }
                }
                for try await site in group { detailed[site.id] = site }
            }
            monitoringSites = detailed
            monitoringError = nil
        } catch {
            monitoringError = error.localizedDescription
        }
    }
}

private enum ProjectDetailSection: String, CaseIterable, Identifiable {
    case overview
    case security

    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Overview"
        case .security: "Security & Maintenance"
        }
    }
}

private struct ProjectCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectItem
    let monitoringSite: MonitoringSite?
    let tasks: [TaskItem]

    let onOpen: () -> Void
    let onOpenSecurity: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    @State private var repositorySnapshot: RepositorySnapshot?
    @State private var repositoryError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.title3.bold())
                        .lineLimit(2)
                    if !project.type.isEmpty {
                        Text(project.type.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if !project.client.isEmpty {
                        Label(project.client, systemImage: "person.crop.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Menu {
                    Button("Open", systemImage: "arrow.up.right.square", action: onOpen)
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    Divider()
                    Button(
                        project.isArchived ? "Restore" : "Archive",
                        systemImage: project.isArchived ? "tray.and.arrow.up" : "archivebox",
                        action: onArchive
                    )
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Project actions")
            }

            HStack {
                Picker("Status", selection: Binding(
                    get: { project.status },
                    set: { newStatus in
                        project.status = newStatus
                        project.updatedAt = .now
                        try? modelContext.save()
                    }
                )) {
                    ForEach(ProjectStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
                .labelsHidden()

                Spacer()
                PriorityBadge(priority: project.priority)
            }

            if let dueDate = project.dueDate {
                DueDateBadge(date: dueDate, status: project.status)
            }

            if let waitingDays = project.waitingDays() {
                Label("Waiting on client · \(waitingDays) day\(waitingDays == 1 ? "" : "s")", systemImage: "hourglass")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            SiteHealthPanel(
                health: MonitoringHealth.evaluate(site: monitoringSite, connected: project.hasMonitoringSite),
                site: monitoringSite,
                isConnected: project.hasMonitoringSite,
                onOpenSecurity: onOpenSecurity
            )

            if project.mode == .ongoing {
                ongoingActivity
            } else {
                ProgressView(value: taskProgress)
                    .tint(.orange)
                HStack {
                    Text("Progress")
                    Text("\(completedTaskCount)/\(tasks.count) tasks")
                        .foregroundStyle(tasks.isEmpty ? .tertiary : .secondary)
                    Spacer()
                    Text(taskProgress, format: .percent.precision(.fractionLength(0)))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !project.nextAction.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT ACTION")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(project.nextAction).lineLimit(2)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.05))
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .contain)
        .accessibilityHint("Open project details")
        .task(id: project.repositoryBookmarkData) {
            await refreshRepository()
        }
    }

    private var completedTaskCount: Int { tasks.filter(\.isCompleted).count }

    private var taskProgress: Double {
        guard !tasks.isEmpty else { return project.progress }
        return Double(completedTaskCount) / Double(tasks.count)
    }

    private var ongoingActivity: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                RepositoryHealthBadge(
                    health: RepositoryHealth.evaluate(
                        status: project.status,
                        dueDate: project.dueDate,
                        snapshot: repositorySnapshot
                    )
                )
                Spacer()
                Text("ONGOING CLIENT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }

            if let repositorySnapshot {
                HStack(spacing: 12) {
                    Label(repositorySnapshot.branch, systemImage: "arrow.triangle.branch")
                    Label("\(repositorySnapshot.dirtyFileCount) changed", systemImage: "pencil.and.list.clipboard")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Text(repositorySnapshot.lastCommitMessage)
                        .lineLimit(1)
                    Spacer()
                    if let date = repositorySnapshot.lastCommitDate {
                        Text(date, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            } else {
                Label(
                    repositoryError ?? "Connect a local repository in project details",
                    systemImage: project.hasRepository ? "exclamationmark.triangle" : "folder.badge.plus"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
        }
    }

    private func refreshRepository() async {
        guard project.mode == .ongoing, let bookmark = project.repositoryBookmarkData else {
            repositorySnapshot = nil
            repositoryError = nil
            return
        }
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

private struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectItem
    @Binding var selectedSection: ProjectDetailSection
    let monitoringSite: MonitoringSite?
    let tasks: [TaskItem]
    let monitoringError: String?
    let isRefreshingMonitoring: Bool
    let onRefreshMonitoring: () -> Void
    let onBack: () -> Void

    @State private var savedAt: Date?
    @State private var repositorySnapshot: RepositorySnapshot?
    @State private var repositoryError: String?
    @State private var isRefreshingRepository = false
    @State private var showingRepositoryPicker = false
    @State private var showingMonitoringSetup = false
    @State private var showingNewTask = false

    private var snapshot: ProjectSnapshot {
        ProjectSnapshot(project: project)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Button(action: onBack) {
                    Label("Projects", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Picker("Project section", selection: $selectedSection) {
                    ForEach(ProjectDetailSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 460)

                if selectedSection == .overview {
                    VStack(alignment: .leading, spacing: 10) {
                    TextField("Project name", text: $project.name)
                        .textFieldStyle(.plain)
                        .font(.largeTitle.bold())

                    TextField("Client", text: $project.client)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Picker("Status", selection: $project.status) {
                            ForEach(ProjectStatus.allCases) { status in
                                Text(status.title).tag(status)
                            }
                        }
                        Picker("Priority", selection: $project.priority) {
                            ForEach(ProjectPriority.allCases) { priority in
                                Text(priority.title).tag(priority)
                            }
                        }
                        Picker("Mode", selection: $project.mode) {
                            ForEach(ProjectMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        Spacer()
                        if let savedAt {
                            Label("Saved", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Last saved \(savedAt.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                    }

                    if project.mode == .ongoing {
                        HStack(spacing: 16) {
                        MetricCard(
                            title: "Health",
                            value: RepositoryHealth.evaluate(
                                status: project.status,
                                dueDate: project.dueDate,
                                snapshot: repositorySnapshot
                            ).title,
                            systemImage: "heart.text.square"
                        )
                        MetricCard(title: "Branch", value: repositorySnapshot?.branch ?? "Not connected", systemImage: "arrow.triangle.branch")
                        MetricCard(title: "Commits · 30d", value: "\(repositorySnapshot?.commitsInLast30Days ?? 0)", systemImage: "point.3.connected.trianglepath.dotted")
                        }
                    } else {
                        HStack(spacing: 16) {
                            MetricCard(title: "Progress", value: taskProgress.formatted(.percent.precision(.fractionLength(0))), systemImage: "chart.line.uptrend.xyaxis")
                            MetricCard(title: "Tasks", value: "\(completedTaskCount) / \(tasks.count)", systemImage: "checklist")
                            MetricCard(title: "Priority", value: project.priority.title, systemImage: "flag.fill")
                        }
                    }

                    if let waitingDays = project.waitingDays() {
                        Label("Waiting on client for \(waitingDays) day\(waitingDays == 1 ? "" : "s")", systemImage: "hourglass")
                            .foregroundStyle(.orange)
                    }

                    projectTasksSection

                    GroupBox("Project details") {
                        VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("Type") {
                            TextField("Website Build", text: $project.type)
                                .frame(maxWidth: 360)
                        }
                        LabeledContent("Project mode") {
                            VStack(alignment: .trailing, spacing: 3) {
                                Picker("Project mode", selection: $project.mode) {
                                    ForEach(ProjectMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                Text(project.mode.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        OptionalDateEditor(label: "Start date", date: $project.startDate)
                        OptionalDateEditor(label: "Due date", date: $project.dueDate)
                        LabeledContent("Tags") {
                            TextField("WordPress, Retainer", text: $project.tagsRawValue)
                                .frame(maxWidth: 360)
                        }
                        }
                        .padding(8)
                    }

                    if project.mode == .ongoing {
                        repositorySection
                    }

                    monitoringSection

                    GroupBox("Description") {
                        TextField("Project scope, context and goals", text: $project.summary, axis: .vertical)
                            .lineLimit(5...10)
                            .textFieldStyle(.plain)
                            .padding(8)
                    }

                    GroupBox("Next action") {
                        TextField("What should happen next?", text: $project.nextAction, axis: .vertical)
                            .lineLimit(2...5)
                            .textFieldStyle(.plain)
                            .padding(8)
                    }
                } else {
                    SecurityMaintenanceView(
                        project: project,
                        site: monitoringSite,
                        apiError: monitoringError,
                        isRefreshing: isRefreshingMonitoring,
                        onRefresh: onRefreshMonitoring,
                        onConfigure: { showingMonitoringSetup = true }
                    )
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
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
        .sheet(isPresented: $showingMonitoringSetup) {
            ProjectMonitoringSheet(project: project)
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView(projectID: project.id)
        }
    }

    private var completedTaskCount: Int { tasks.filter(\.isCompleted).count }

    private var taskProgress: Double {
        guard !tasks.isEmpty else { return project.progress }
        return Double(completedTaskCount) / Double(tasks.count)
    }

    private var projectTasksSection: some View {
        GroupBox("Project tasks") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tasks.isEmpty ? "No linked tasks yet" : "\(completedTaskCount) of \(tasks.count) complete")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add Task", systemImage: "plus") { showingNewTask = true }
                }

                ForEach(tasks.prefix(8)) { task in
                    HStack(spacing: 10) {
                        Button {
                            task.isCompleted.toggle()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isCompleted ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                        Text(task.title)
                            .strikethrough(task.isCompleted)
                        if task.isBlocked {
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
                }
            }
            .padding(8)
        }
    }

    private var monitoringSection: some View {
        GroupBox("Website monitoring") {
            HStack(spacing: 14) {
                Image(systemName: project.hasMonitoringSite ? "checkmark.shield.fill" : "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(project.hasMonitoringSite ? .green : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(project.hasMonitoringSite ? "Connected to JARVIS" : "No monitored website")
                        .font(.headline)
                    Text(project.hasMonitoringSite
                         ? "\(project.monitoringPlatform.title) · \(project.monitoringWebsiteURL)"
                         : "Register this project's website and receive a dedicated reporter token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button(project.hasMonitoringSite ? "Connection Settings…" : "Connect Website…") {
                    showingMonitoringSetup = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(8)
        }
    }

    private var repositorySection: some View {
        GroupBox("Local repository") {
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
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
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
            .padding(8)
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

private struct SiteHealthPanel: View {
    let health: MonitoringHealth
    let site: MonitoringSite?
    let isConnected: Bool
    let onOpenSecurity: () -> Void

    private var updateCount: Int { site?.latestSnapshot?.pendingUpdateCount ?? 0 }
    private var findingCount: Int { site?.openFindingsCount ?? 0 }

    var body: some View {
        HStack(spacing: 18) {
            SiteHealthGauge(health: health, compact: true)
                .frame(width: 112, height: 72)

            VStack(alignment: .leading, spacing: 4) {
                Text("SITE HEALTH")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(health.score.map(String.init) ?? "—")
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                    Text(health.label)
                        .font(.headline)
                        .foregroundStyle(health.colour)
                }

                if isConnected {
                    Text("\(updateCount) updates · \(findingCount) vulnerabilit\(findingCount == 1 ? "y" : "ies")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(lastObservedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Connect this project to its monitored website")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button(action: onOpenSecurity) {
                Text(isConnected ? "Security ›" : "Connect site")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.035))
        }
    }

    private var lastObservedText: String {
        guard let date = health.lastObservedAt else { return "No completed outside check yet" }
        return "Checked \(date.formatted(.relative(presentation: .named)))"
    }
}

private struct SiteHealthGauge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let health: MonitoringHealth
    var compact = false

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height - (compact ? 7 : 10))
                let radius = min(size.width * 0.40, size.height - (compact ? 12 : 18))
                let lineWidth = compact ? 7.0 : 10.0

                drawBand(context: &context, center: center, radius: radius, lineWidth: lineWidth, range: 0...49, colour: .red)
                drawBand(context: &context, center: center, radius: radius, lineWidth: lineWidth, range: 50...79, colour: .orange)
                drawBand(context: &context, center: center, radius: radius, lineWidth: lineWidth, range: 80...100, colour: Color(red: 0.24, green: 0.81, blue: 0.56))

                guard health.score != nil else { return }
                context.fill(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(.white))
            }

            if let score = health.score {
                SiteHealthGaugeNeedle(score: Double(score), compact: compact)
                    .stroke(
                        .white.opacity(0.95),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.75), value: score)
            }
        }
        .opacity(health.state == .stale ? 0.5 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func drawBand(
        context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        lineWidth: Double,
        range: ClosedRange<Int>,
        colour: Color
    ) {
        let start = 180 + (180 * Double(range.lowerBound) / 100)
        let end = 180 + (180 * Double(range.upperBound + 1) / 100)
        let isActive: Bool
        if let score = health.score {
            isActive = range.contains(score)
        } else {
            isActive = false
        }
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(start),
            endAngle: .degrees(end),
            clockwise: false
        )
        context.stroke(
            path,
            with: .color(colour.opacity(isActive ? 1 : 0.35)),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
        )
    }

    private var accessibilityText: String {
        if let score = health.score {
            return "Site health \(score) of 100, \(health.label.lowercased())"
        }
        return "Site health \(health.label.lowercased())"
    }

}

private struct SiteHealthGaugeNeedle: Shape {
    var score: Double
    let compact: Bool

    var animatableData: Double {
        get { score }
        set { score = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.width / 2, y: rect.height - (compact ? 7 : 10))
        let radius = min(rect.width * 0.40, rect.height - (compact ? 12 : 18))
        let radians = .pi + (.pi * min(max(score, 0), 100) / 100)
        let needleLength = radius * 0.72
        let end = CGPoint(
            x: center.x + cos(radians) * needleLength,
            y: center.y + sin(radians) * needleLength
        )
        var path = Path()
        path.move(to: center)
        path.addLine(to: end)

        return path
    }
}

private struct SecurityMaintenanceView: View {
    @AppStorage("monitoring.apiBaseURL") private var monitoringAPIBaseURL = MonitoringAPIService.defaultBaseURL
    let project: ProjectItem
    let site: MonitoringSite?
    let apiError: String?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onConfigure: () -> Void
    @State private var findingMessage: String?

    private let apiService = MonitoringAPIService()
    private let adminCredentialStore = MonitoringAdminCredentialStore()

    private var health: MonitoringHealth {
        MonitoringHealth.evaluate(site: site, connected: project.hasMonitoringSite)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            securityHeader

            if let apiError {
                Label("Monitoring API unavailable · showing the last available project connection", systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .help(apiError)
            }

            if let findingMessage {
                Text(findingMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let site {
                vulnerabilitySection(site)
                updatesSection(site)
                applicationHealthSection(site)
                environmentSection(site)
                scoreBreakdownSection
                historySection(site)
            } else {
                ContentUnavailableView {
                    Label(project.hasMonitoringSite ? "Monitoring data unavailable" : "Site not connected", systemImage: "waveform.path.ecg")
                } description: {
                    Text(project.hasMonitoringSite
                         ? "Refresh the API connection or review its settings. JARVIS will not substitute a fake healthy state."
                         : "Connect this project to a monitored website to display security and maintenance data.")
                } actions: {
                    Button("Connection Settings…", action: onConfigure)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
    }

    private var securityHeader: some View {
        GroupBox {
            HStack(spacing: 22) {
                SiteHealthGauge(health: health)
                    .frame(width: 170, height: 105)

                VStack(alignment: .leading, spacing: 8) {
                    Text("SITE HEALTH")
                        .font(.caption.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(health.score.map(String.init) ?? "—")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(health.label)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(health.colour)
                    }
                    if let observed = health.lastObservedAt {
                        Text("Last observed \(observed.formatted(.relative(presentation: .named)))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Waiting for the first completed outside check")
                            .foregroundStyle(.secondary)
                    }
                    if let site {
                        Text("Sources: public reachability · reporter · dependency inventory")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(site.url)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 10) {
                    Button("Refresh now", systemImage: "arrow.clockwise", action: onRefresh)
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isRefreshing)
                    Button("Connection Settings…", action: onConfigure)
                }
            }
            .padding(10)
        }
    }

    private func vulnerabilitySection(_ site: MonitoringSite) -> some View {
        GroupBox("Vulnerabilities") {
            VStack(alignment: .leading, spacing: 10) {
                let open = site.findings.filter { $0.status == "open" }
                if open.isEmpty {
                    Label(
                        site.openFindingsCount == 0 ? "No open vulnerabilities reported" : "Finding details have not loaded",
                        systemImage: site.openFindingsCount == 0 ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(site.openFindingsCount == 0 ? .green : .orange)
                } else {
                    ForEach(open.sorted { severityRank($0.severity) < severityRank($1.severity) }) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Text(finding.severity.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(severityColour(finding.severity))
                                .frame(width: 62, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(finding.title).font(.headline)
                                Text("\(finding.componentType.capitalized) · \(finding.slug)" + (finding.fixedIn.map { " · Fixed in \($0)" } ?? ""))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let urlText = finding.referenceURL, let url = URL(string: urlText) {
                                Link("Reference", destination: url)
                            }
                            Menu {
                                Button("Mark as Handled") { Task { await updateFinding(finding, status: "handled") } }
                                Button("Ignore") { Task { await updateFinding(finding, status: "ignored") } }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .menuStyle(.borderlessButton)
                        }
                        if finding.id != open.last?.id { Divider() }
                    }
                }
            }
            .padding(8)
        }
    }

    private func updatesSection(_ site: MonitoringSite) -> some View {
        GroupBox("Updates") {
            VStack(alignment: .leading, spacing: 10) {
                let updates = site.latestSnapshot?.components.filter { $0.updateAvailable == true } ?? []
                if updates.isEmpty {
                    Label("No component updates reported", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(updates) { component in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.name).font(.headline)
                                Text(component.ecosystem.capitalized).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(component.version).monospaced().foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                            Text(component.latestVersion ?? "Update available").monospaced()
                        }
                    }
                }
                if let notCovered = site.latestSnapshot?.notCovered, !notCovered.isEmpty {
                    Label("Not covered: \(notCovered.joined(separator: ", "))", systemImage: "questionmark.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private func applicationHealthSection(_ site: MonitoringSite) -> some View {
        GroupBox(site.platform == .wordpress ? "WordPress Site Health" : "Application health") {
            VStack(alignment: .leading, spacing: 10) {
                let checks = site.latestSnapshot?.siteHealth ?? []
                if checks.isEmpty {
                    Text("No application health checks reported.").foregroundStyle(.secondary)
                } else {
                    ForEach(checks) { check in
                        HStack {
                            Image(systemName: check.status.lowercased() == "pass" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(check.status.lowercased() == "pass" ? .green : .orange)
                            Text(check.label)
                            Spacer()
                            Text(check.message ?? check.status.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func environmentSection(_ site: MonitoringSite) -> some View {
        GroupBox("Environment") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                environmentRow("Status", site.status.rawValue.capitalized)
                environmentRow("HTTP", site.lastStatusCode.map(String.init) ?? "Awaiting check")
                environmentRow("Response", site.lastResponseMilliseconds.map { "\($0) ms" } ?? "Awaiting check")
                environmentRow("Uptime · 30 d", site.uptime30DayPercent.map { String(format: "%.2f%%", $0) } ?? "Not enough history")
                environmentRow("PHP", site.latestSnapshot?.phpVersion ?? "Not reported")
                environmentRow("SSL expiry", site.sslExpiresAt?.formatted(date: .abbreviated, time: .omitted) ?? "Awaiting check")
                environmentRow("Last heartbeat", site.lastHeartbeatAt?.formatted(.relative(presentation: .named)) ?? "Never")
                environmentRow("Application", site.latestSnapshot?.applicationName ?? site.name)
                environmentRow("Deployment", site.latestSnapshot?.applicationVersion ?? "Not reported")
            }
            .padding(8)
        }
    }

    private var scoreBreakdownSection: some View {
        GroupBox("Score breakdown") {
            VStack(alignment: .leading, spacing: 10) {
                if health.state == .awaitingChecks {
                    Text("A score will appear after the backend completes its first public reachability check.")
                        .foregroundStyle(.secondary)
                } else if health.deductions.isEmpty {
                    Label("No deductions", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ForEach(health.deductions) { deduction in
                        HStack {
                            Text(deduction.reason)
                            Spacer()
                            Text("−\(deduction.points)").foregroundStyle(.orange).monospacedDigit()
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func historySection(_ site: MonitoringSite) -> some View {
        GroupBox("Incident history") {
            VStack(alignment: .leading, spacing: 10) {
                if site.incidents.isEmpty {
                    Text("No incidents recorded.").foregroundStyle(.secondary)
                } else {
                    ForEach(site.incidents) { incident in
                        HStack {
                            Label(incident.type.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: incident.endedAt == nil ? "exclamationmark.triangle.fill" : "checkmark.circle")
                            Spacer()
                            if let started = incident.startedAt {
                                Text(started.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                            }
                            Text(incident.endedAt == nil ? "Open" : "Recovered")
                                .foregroundStyle(incident.endedAt == nil ? .red : .green)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func environmentRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func severityRank(_ severity: String) -> Int {
        switch severity.lowercased() {
        case "critical": 0
        case "high": 1
        case "medium": 2
        default: 3
        }
    }

    private func severityColour(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "critical": .red
        case "high": .orange
        case "medium": .yellow
        default: .secondary
        }
    }

    @MainActor
    private func updateFinding(_ finding: MonitoringFinding, status: String) async {
        guard let token = adminCredentialStore.read() else {
            findingMessage = "Save the site-registration token in Connection Settings before changing a finding."
            return
        }
        do {
            try await apiService.updateFinding(
                baseURLText: monitoringAPIBaseURL,
                adminToken: token,
                findingID: finding.id,
                status: status
            )
            findingMessage = status == "handled" ? "Finding marked as handled." : "Finding ignored."
            onRefresh()
        } catch {
            findingMessage = error.localizedDescription
        }
    }
}

private struct ProjectMonitoringSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("monitoring.apiBaseURL") private var monitoringAPIBaseURL = MonitoringAPIService.defaultBaseURL

    @Bindable var project: ProjectItem
    @State private var websiteURL: String
    @State private var platform: MonitoringPlatform
    @State private var adminToken = ""
    @State private var hasStoredAdminToken = false
    @State private var rememberAdminToken = true
    @State private var isConnecting = false
    @State private var statusMessage: String?
    @State private var issuedIngestToken: String?

    private let apiService = MonitoringAPIService()
    private let readCredentialStore = MonitoringAPICredentialStore()
    private let adminCredentialStore = MonitoringAdminCredentialStore()
    private let siteCredentialStore = MonitoringSiteCredentialStore()

    init(project: ProjectItem) {
        self.project = project
        _websiteURL = State(initialValue: project.monitoringWebsiteURL)
        _platform = State(initialValue: project.monitoringPlatform)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Website") {
                    TextField("https://example.com", text: $websiteURL)
                        .textContentType(.URL)
                    Picker("Platform", selection: $platform) {
                        ForEach(MonitoringPlatform.allCases) { platform in
                            Text(platform.title).tag(platform)
                        }
                    }
                }

                if project.hasMonitoringSite {
                    Section("Connection") {
                        LabeledContent("Status", value: "Connected")
                        LabeledContent("Site ID", value: project.monitoringSiteID)
                            .textSelection(.enabled)
                        if let connectedAt = project.monitoringConnectedAt {
                            LabeledContent("Connected", value: connectedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        Button("Copy Reporter Token", systemImage: "key") {
                            copyReporterToken()
                        }
                        Button("Rotate Reporter Token", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await rotateReporterToken() }
                        }
                    }

                    Section("Administrative access") {
                        SecureField(
                            hasStoredAdminToken ? "Use saved site-registration token" : "Paste an admin site-registration token",
                            text: $adminToken
                        )
                        .textContentType(.password)

                        Toggle("Remember registration token in Keychain", isOn: $rememberAdminToken)

                        Text("Required only when saving changes to the monitored website. The existing Site ID, reporter token, and monitoring history will be preserved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Site registration") {
                        SecureField(
                            hasStoredAdminToken ? "Use saved site-registration token" : "Paste an admin site-registration token",
                            text: $adminToken
                        )
                        .textContentType(.password)

                        Toggle("Remember registration token in Keychain", isOn: $rememberAdminToken)

                        Text("The registration token creates the site record. The reporter token returned by the API is stored separately for this project.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if readCredentialStore.read() != nil {
                            Text("Already monitored? JARVIS will attach the existing site using its saved read-only connection; no registration token is needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let statusMessage {
                    Section {
                        Label(statusMessage, systemImage: project.hasMonitoringSite ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(project.hasMonitoringSite ? .green : .orange)
                    }
                }

                Section("Reporter setup") {
                    Text(project.hasMonitoringSite
                         ? "Install or configure the reporter on the website, then use Copy Reporter Token to place its dedicated token in the host's secret manager."
                         : "Connecting registers the site only. JARVIS never installs code or changes hosting settings without your approval.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Website Monitoring")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                if !project.hasMonitoringSite {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Connect Website") {
                            Task { await connectWebsite() }
                        }
                        .keyboardShortcut(.defaultAction)
                            .disabled(!canConnect || isConnecting)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save Changes") {
                            Task { await saveChanges() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSaveChanges || isConnecting)
                    }
                }
            }
            .overlay {
                if isConnecting {
                    ZStack {
                        Color.black.opacity(0.12)
                        ProgressView("Connecting website…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .frame(width: 620, height: 560)
        .onAppear {
            hasStoredAdminToken = adminCredentialStore.read() != nil
            if project.hasMonitoringSite {
                issuedIngestToken = siteCredentialStore.read(projectID: project.id)
            }
        }
    }

    private var canConnect: Bool {
        !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !websiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (readCredentialStore.read() != nil
                || hasStoredAdminToken
                || !adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var canSaveChanges: Bool {
        project.hasMonitoringSite
            && !project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !websiteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (hasStoredAdminToken || !adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    private func connectWebsite() async {
        isConnecting = true
        defer { isConnecting = false }

        do {
            let normalizedURL = try apiService.normalizedWebsiteURL(from: websiteURL).absoluteString
            websiteURL = normalizedURL

            if let readToken = readCredentialStore.read(),
               let existingSite = try await apiService.existingSite(
                   baseURLText: monitoringAPIBaseURL,
                   readToken: readToken,
                   websiteURLText: normalizedURL
               ) {
                try attach(existingSite)
                statusMessage = "Existing monitored website attached to this project."
                return
            }
        } catch {
            statusMessage = error.localizedDescription
            return
        }

        let token = adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? adminCredentialStore.read()
            : adminToken
        guard let token, !token.isEmpty else {
            statusMessage = "This website is not registered yet. Paste an admin site-registration token to add it."
            return
        }

        do {
            let registration = try await apiService.registerSite(
                baseURLText: monitoringAPIBaseURL,
                adminToken: token,
                name: project.name,
                websiteURLText: websiteURL,
                platform: platform
            )
            try siteCredentialStore.save(registration.ingestToken, projectID: project.id)
            if rememberAdminToken {
                try? adminCredentialStore.save(token)
            } else {
                try? adminCredentialStore.delete()
            }

            project.monitoringWebsiteURL = registration.url
            project.monitoringPlatform = registration.platform
            project.monitoringSiteID = registration.id
            project.monitoringConnectedAt = .now
            project.updatedAt = .now
            try modelContext.save()

            issuedIngestToken = registration.ingestToken
            adminToken = ""
            hasStoredAdminToken = rememberAdminToken
            statusMessage = "Website registered. Configure its reporter to begin sending health data."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func attach(_ site: MonitoringSite) throws {
        project.monitoringWebsiteURL = site.url
        project.monitoringPlatform = site.platform
        project.monitoringSiteID = site.id
        project.monitoringConnectedAt = .now
        project.updatedAt = .now
        try modelContext.save()
    }

    @MainActor
    private func saveChanges() async {
        let token = adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? adminCredentialStore.read()
            : adminToken
        guard let token, !token.isEmpty else {
            statusMessage = "Paste an admin site-registration token to save monitoring changes."
            return
        }

        isConnecting = true
        defer { isConnecting = false }

        do {
            let updatedSite = try await apiService.updateSite(
                baseURLText: monitoringAPIBaseURL,
                adminToken: token,
                siteID: project.monitoringSiteID,
                name: project.name,
                websiteURLText: websiteURL,
                platform: platform
            )

            if rememberAdminToken {
                try adminCredentialStore.save(token)
            } else {
                try? adminCredentialStore.delete()
            }

            websiteURL = updatedSite.url
            project.monitoringWebsiteURL = updatedSite.url
            project.monitoringPlatform = updatedSite.platform
            project.updatedAt = .now
            try modelContext.save()

            adminToken = ""
            hasStoredAdminToken = rememberAdminToken
            statusMessage = "Monitoring settings updated. Existing history and reporter access were preserved."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func copyReporterToken() {
        let token = issuedIngestToken ?? siteCredentialStore.read(projectID: project.id)
        guard let token else {
            statusMessage = "The reporter token is not stored on this Mac. Rotate it before configuring a new reporter."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        statusMessage = "Reporter token copied. Paste it only into the website host's secret manager."
    }

    @MainActor
    private func rotateReporterToken() async {
        let token = adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? adminCredentialStore.read()
            : adminToken
        guard let token, !token.isEmpty else {
            statusMessage = "Paste or save an admin site-registration token before rotating the reporter token."
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let replacement = try await apiService.rotateReporterToken(
                baseURLText: monitoringAPIBaseURL,
                adminToken: token,
                siteID: project.monitoringSiteID
            )
            try siteCredentialStore.save(replacement, projectID: project.id)
            issuedIngestToken = replacement
            statusMessage = "Reporter token rotated. The previous token is revoked; update the website before its next heartbeat."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

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
                    .disabled(draft.trimmedName.isEmpty)
                }
            }
        }
        .frame(width: 560, height: 600)
    }

    private func save() {
        if let project {
            draft.apply(to: project)
        } else {
            modelContext.insert(draft.makeProject())
        }
        try? modelContext.save()
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
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    func makeProject() -> ProjectItem {
        ProjectItem(
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
    let monitoringWebsiteURL: String
    let monitoringPlatform: String
    let monitoringSiteID: String
    let monitoringConnectedAt: Date?

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
        monitoringWebsiteURL = project.monitoringWebsiteURL
        monitoringPlatform = project.monitoringPlatformRawValue
        monitoringSiteID = project.monitoringSiteID
        monitoringConnectedAt = project.monitoringConnectedAt
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

private struct PriorityBadge: View {
    let priority: ProjectPriority

    var body: some View {
        Text(priority.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(priority == .urgent ? .red : .secondary)
            .background(.quaternary, in: Capsule())
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

private struct DueDateBadge: View {
    let date: Date
    let status: ProjectStatus

    private var state: DueState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let dueDay = calendar.startOfDay(for: date)
        guard status != .completed, status != .archived else { return .normal }
        if dueDay < today { return .overdue }
        if let sevenDays = calendar.date(byAdding: .day, value: 7, to: today), dueDay <= sevenDays {
            return .dueSoon
        }
        return .normal
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.systemImage)
            Text(state.label(for: date))
        }
        .font(.caption.weight(state == .normal ? .regular : .semibold))
        .foregroundStyle(state.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(state.color.opacity(0.12), in: Capsule())
    }

    private enum DueState: Equatable {
        case overdue
        case dueSoon
        case normal

        var color: Color {
            switch self {
            case .overdue: .red
            case .dueSoon: .orange
            case .normal: .secondary
            }
        }

        var systemImage: String {
            switch self {
            case .overdue: "exclamationmark.triangle.fill"
            case .dueSoon: "clock.fill"
            case .normal: "calendar"
            }
        }

        func label(for date: Date) -> String {
            let formatted = date.formatted(.dateTime.month(.abbreviated).day())
            return switch self {
            case .overdue: "Overdue · \(formatted)"
            case .dueSoon: "Due soon · \(formatted)"
            case .normal: "Due \(formatted)"
            }
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title3.bold())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
