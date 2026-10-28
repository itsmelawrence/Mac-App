import SwiftData
import SwiftUI

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \ProjectItem.name) private var projects: [ProjectItem]

    @State private var showingNewTask = false
    @State private var searchText = ""
    @State private var selectedScope: TaskQueueScope = .open
    @State private var selectedProjectID: UUID?
    @State private var taskPendingDeletion: TaskItem?

    private var summary: TaskQueueSummary { TaskQueueEngine.summary(for: tasks) }
    private var focusTask: TaskItem? { TaskQueueEngine.focusTask(from: tasks) }
    private var activeProjects: [ProjectItem] { projects.filter { !$0.isArchived } }

    private var visibleTasks: [TaskItem] {
        let matching = tasks.filter { task in
            guard TaskQueueEngine.matches(task, scope: selectedScope) else { return false }
            if let selectedProjectID, task.projectID != selectedProjectID { return false }
            guard !searchText.isEmpty else { return true }

            let projectName = projects.first { $0.id == task.projectID }?.name ?? ""
            return task.title.localizedCaseInsensitiveContains(searchText)
                || task.notes.localizedCaseInsensitiveContains(searchText)
                || task.blockedReason.localizedCaseInsensitiveContains(searchText)
                || projectName.localizedCaseInsensitiveContains(searchText)
        }
        return TaskQueueEngine.sorted(matching)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                missionHeader
                statusRail
                focusPanel

                HStack(alignment: .top, spacing: 16) {
                    queuePanel.frame(maxWidth: .infinity)
                    controlsPanel.frame(width: 286)
                }
            }
            .padding(28)
        }
        .background(missionBackground)
        .navigationTitle("Tasks")
        .searchable(text: $searchText, prompt: "Search missions, notes, or projects")
        .toolbar {
            Button { showingNewTask = true } label: {
                Label("New task", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .sheet(isPresented: $showingNewTask) { NewTaskView() }
        .alert("Delete this task?", isPresented: deletionAlertBinding, presenting: taskPendingDeletion) { task in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { TaskStore.delete(task, from: modelContext) }
        } message: { task in
            Text("“\(task.title)” will be permanently removed.")
        }
    }

    private var deletionAlertBinding: Binding<Bool> {
        Binding(
            get: { taskPendingDeletion != nil },
            set: { if !$0 { taskPendingDeletion = nil } }
        )
    }

    private var missionBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.012, green: 0.028, blue: 0.052), Color(nsColor: .windowBackgroundColor)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var missionHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Mission Queue")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(summary.open == 0 ? "The board is clear. Suspiciously efficient." : "Prioritised work across every active operation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if summary.overdue > 0 || summary.blocked > 0 {
                HStack(spacing: 7) {
                    Circle().fill(Color.orange).frame(width: 7, height: 7)
                    Text("\(summary.overdue + summary.blocked) require attention")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.orange)
            }
            Button { showingNewTask = true } label: {
                Label("New Mission", systemImage: "plus.circle.fill")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
    }

    private var statusRail: some View {
        HStack(spacing: 0) {
            TaskMetric(title: "Open", value: summary.open, tint: .primary)
            TaskMetricDivider()
            TaskMetric(title: "Due today", value: summary.today, tint: summary.today > 0 ? .cyan : .secondary)
            TaskMetricDivider()
            TaskMetric(title: "Overdue", value: summary.overdue, tint: summary.overdue > 0 ? .red : .secondary)
            TaskMetricDivider()
            TaskMetric(title: "Blocked", value: summary.blocked, tint: summary.blocked > 0 ? .orange : .secondary)
            TaskMetricDivider()
            TaskMetric(title: "Completed", value: summary.completed, tint: .green)
        }
        .padding(.vertical, 14)
        .taskSurface(cornerRadius: 14)
    }

    @ViewBuilder
    private var focusPanel: some View {
        if let task = focusTask {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Priority now", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text(task.priority.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(priorityColor(task.priority))
                }

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        HStack(spacing: 12) {
                            if let projectName = projectName(for: task) {
                                Label(projectName, systemImage: "square.stack.3d.up")
                            } else {
                                Label("Inbox", systemImage: "tray")
                            }
                            if let dueDate = task.dueDate {
                                Label(dueText(dueDate), systemImage: dueDate < .now ? "clock.badge.exclamationmark" : "calendar")
                                    .foregroundStyle(dueDate < .now ? Color.red : Color.secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Mark Complete", systemImage: "checkmark.circle.fill") {
                        TaskStore.setCompleted(task, true)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .padding(20)
            .taskSurface(cornerRadius: 16, highlighted: true)
        } else {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.seal.fill").font(.title).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("No active mission").font(.headline)
                    Text("Everything is either complete or waiting for your next instruction.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskSurface(cornerRadius: 16, highlighted: true)
        }
    }

    private var queuePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("\(selectedScope.title) queue", systemImage: selectedScope.systemImage)
                    .font(.headline)
                Spacer()
                Text("\(visibleTasks.count) \(visibleTasks.count == 1 ? "mission" : "missions")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)

            Divider().opacity(0.5)

            if visibleTasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: searchText.isEmpty ? selectedScope.systemImage : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "Nothing in this queue" : "No matching missions")
                        .font(.headline)
                    Text(searchText.isEmpty ? emptyQueueMessage : "Try a broader search or another filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 250)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleTasks.enumerated()), id: \.element.id) { index, task in
                        MissionTaskRow(
                            task: task,
                            projectName: projectName(for: task),
                            onDelete: { taskPendingDeletion = task }
                        )
                        if index < visibleTasks.count - 1 { Divider().opacity(0.45).padding(.leading, 58) }
                    }
                }
            }
        }
        .taskSurface(cornerRadius: 16)
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("QUEUE VIEW")
                    .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                ForEach(TaskQueueScope.allCases) { scope in
                    Button { selectedScope = scope } label: {
                        HStack(spacing: 10) {
                            Image(systemName: scope.systemImage).frame(width: 18)
                            Text(scope.title)
                            Spacer()
                            Text("\(count(for: scope))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(selectedScope == scope ? Color.cyan : Color.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(selectedScope == scope ? Color.cyan.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                Text("OPERATION")
                    .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                Picker("Project", selection: $selectedProjectID) {
                    Text("All projects").tag(UUID?.none)
                    ForEach(activeProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            Divider().opacity(0.5)

            completionPanel
        }
        .padding(18)
        .taskSurface(cornerRadius: 16)
    }

    private var completionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MOMENTUM")
                    .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
                Spacer()
                Text(completionPercentage, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.green)
            }
            ProgressView(value: completionPercentage).tint(.green)
            Text(tasks.isEmpty ? "No missions logged yet." : "\(summary.completed) of \(tasks.count) missions resolved.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var completionPercentage: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(summary.completed) / Double(tasks.count)
    }

    private var emptyQueueMessage: String {
        switch selectedScope {
        case .open: "Add a mission when the next objective presents itself."
        case .today: "Nothing is scheduled for today. A rare luxury."
        case .overdue: "No overdue work. Temporal integrity maintained."
        case .blocked: "No blocked work. All routes remain open."
        case .completed: "Completed missions will be archived here."
        }
    }

    private func count(for scope: TaskQueueScope) -> Int {
        switch scope {
        case .open: summary.open
        case .today: summary.today
        case .overdue: summary.overdue
        case .blocked: summary.blocked
        case .completed: summary.completed
        }
    }

    private func projectName(for task: TaskItem) -> String? {
        projects.first { $0.id == task.projectID }?.name
    }

    private func dueText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today at \(date.formatted(date: .omitted, time: .shortened))"
        }
        if Calendar.current.isDateInTomorrow(date) {
            return "Tomorrow at \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: .secondary
        case .normal: .cyan
        case .high: .orange
        case .critical: .red
        }
    }
}

private struct MissionTaskRow: View {
    @Bindable var task: TaskItem
    let projectName: String?
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button { TaskStore.setCompleted(task, !task.isCompleted) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isCompleted ? Color.green : priorityColor)
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Mark pending" : "Mark complete")

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Label(projectName ?? "Inbox", systemImage: projectName == nil ? "tray" : "square.stack.3d.up")
                    if task.isBlocked {
                        Label(task.blockedReason.isEmpty ? "Blocked" : task.blockedReason, systemImage: "hand.raised.fill")
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 7) {
                if let dueDate = task.dueDate {
                    Label(dueLabel(dueDate), systemImage: dueDate < .now && !task.isCompleted ? "clock.badge.exclamationmark" : "calendar")
                        .font(.caption)
                        .foregroundStyle(dueDate < .now && !task.isCompleted ? Color.red : Color.secondary)
                } else {
                    Text("No deadline").font(.caption).foregroundStyle(.tertiary)
                }
                Text(task.priority.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(priorityColor)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contextMenu {
            Button(task.isBlocked ? "Unblock Task" : "Mark as Blocked", systemImage: task.isBlocked ? "hand.thumbsup" : "hand.raised") {
                task.isBlocked.toggle()
                if !task.isBlocked { task.blockedReason = "" }
            }
            Divider()
            Button("Delete Task", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: .secondary
        case .normal: .cyan
        case .high: .orange
        case .critical: .red
        }
    }

    private func dueLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today, \(date.formatted(date: .omitted, time: .shortened))" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct TaskMetric: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }
}

private struct TaskMetricDivider: View {
    var body: some View { Divider().frame(height: 34) }
}

private extension View {
    func taskSurface(cornerRadius: CGFloat, highlighted: Bool = false) -> some View {
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

struct NewTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectItem.name) private var projects: [ProjectItem]

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = true
    @State private var dueDate = Date.now.addingTimeInterval(3_600)
    @State private var priority = TaskPriority.normal
    @State private var projectID: UUID?
    @State private var isBlocked = false
    @State private var blockedReason = ""

    init(projectID: UUID? = nil) {
        _projectID = State(initialValue: projectID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mission") {
                    TextField("Task", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section("Operations") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { priority in Text(priority.title).tag(priority) }
                    }
                    Picker("Project", selection: $projectID) {
                        Text("Inbox / No project").tag(UUID?.none)
                        ForEach(projects.filter { !$0.isArchived }) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    Toggle("Blocked", isOn: $isBlocked)
                    if isBlocked { TextField("What is blocking this task?", text: $blockedReason) }
                }
                Section("Timing") {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate { DatePicker("Due", selection: $dueDate) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Mission")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Mission") { addTask() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 500, height: 500)
    }

    private func addTask() {
        let task = TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority,
            projectID: projectID,
            isBlocked: isBlocked,
            blockedReason: blockedReason.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        TaskStore.add(task, to: modelContext)
        dismiss()
    }
}
