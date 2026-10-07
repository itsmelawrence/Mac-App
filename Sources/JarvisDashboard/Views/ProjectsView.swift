import SwiftData
import SwiftUI

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
    }
}

private struct ProjectDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectItem
    let onBack: () -> Void

    @State private var savedAt: Date?

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
                        Spacer()
                        if let savedAt {
                            Label("Saved", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .help("Last saved \(savedAt.formatted(date: .omitted, time: .shortened))")
                        }
                    }
                }

                HStack(spacing: 16) {
                    MetricCard(title: "Progress", value: project.progress.formatted(.percent.precision(.fractionLength(0))), systemImage: "chart.line.uptrend.xyaxis")
                    MetricCard(title: "Tasks", value: "0 / 0", systemImage: "checklist")
                    MetricCard(title: "Priority", value: project.priority.title, systemImage: "flag.fill")
                }

                GroupBox("Project details") {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("Type") {
                            TextField("Website Build", text: $project.type)
                                .frame(maxWidth: 360)
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
    }

    private func persistChanges() {
        project.updatedAt = .now
        try? modelContext.save()
        savedAt = .now
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
    let startDate: Date?
    let dueDate: Date?
    let summary: String
    let nextAction: String
    let tags: String

    init(project: ProjectItem) {
        name = project.name
        client = project.client
        type = project.type
        status = project.statusRawValue
        priority = project.priorityRawValue
        startDate = project.startDate
        dueDate = project.dueDate
        summary = project.summary
        nextAction = project.nextAction
        tags = project.tagsRawValue
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
