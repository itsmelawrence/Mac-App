import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectItem.updatedAt, order: .reverse) private var projects: [ProjectItem]

    @AppStorage("projects.showArchived") private var showArchived = false
    @State private var showingNewProject = false
    @State private var editingProject: ProjectItem?
    @State private var selectedProject: ProjectItem?
    @State private var projectPendingDeletion: ProjectItem?

    private var visibleProjects: [ProjectItem] {
        projects.filter { showArchived || !$0.isArchived }
    }

    var body: some View {
        Group {
            if let selectedProject {
                ProjectDetailView(project: selectedProject) {
                    self.selectedProject = nil
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 16)], spacing: 16) {
                    ForEach(visibleProjects) { project in
                        ProjectCard(
                            project: project,
                            onOpen: { selectedProject = project },
                            onEdit: { editingProject = project },
                            onDuplicate: { duplicate(project) },
                            onArchive: { archive(project) },
                            onDelete: { projectPendingDeletion = project }
                        )
                    }
                }
                .padding(24)
            }
        }
    }

    @ToolbarContentBuilder
    private var projectToolbar: some ToolbarContent {
        if selectedProject == nil {
            ToolbarItemGroup {
                Menu {
                    Toggle("Show Archived", isOn: $showArchived)
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
}

private struct ProjectCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectItem

    let onOpen: () -> Void
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

            if project.mode == .ongoing {
                ongoingActivity
            } else {
                ProgressView(value: project.progress)
                    .tint(.orange)
                HStack {
                    Text("Progress")
                    Text("0/0 tasks")
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text(project.progress, format: .percent.precision(.fractionLength(0)))
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
    let onBack: () -> Void

    @State private var savedAt: Date?
    @State private var repositorySnapshot: RepositorySnapshot?
    @State private var repositoryError: String?
    @State private var isRefreshingRepository = false
    @State private var showingRepositoryPicker = false
    @State private var showingMonitoringSetup = false

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
                        MetricCard(title: "Progress", value: project.progress.formatted(.percent.precision(.fractionLength(0))), systemImage: "chart.line.uptrend.xyaxis")
                        MetricCard(title: "Tasks", value: "0 / 0", systemImage: "checklist")
                        MetricCard(title: "Priority", value: project.priority.title, systemImage: "flag.fill")
                    }
                }

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
                }
            }
            .overlay {
                if isConnecting {
                    ZStack {
                        Color.black.opacity(0.12)
                        ProgressView("Registering website…")
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
            && (hasStoredAdminToken || !adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @MainActor
    private func connectWebsite() async {
        let token = adminToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? adminCredentialStore.read()
            : adminToken
        guard let token, !token.isEmpty else {
            statusMessage = MonitoringAPIError.missingToken.localizedDescription
            return
        }

        isConnecting = true
        defer { isConnecting = false }

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
