import AppKit
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
    @State private var taskBeingEdited: TaskItem?

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
            VStack(alignment: .leading, spacing: 26) {
                missionHeader
                statusRail
                focusPanel
                queueSection
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1_180)
            .frame(maxWidth: .infinity)
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
        .sheet(isPresented: $showingNewTask) { TaskEditorView() }
        .sheet(item: $taskBeingEdited) { TaskEditorView(editing: $0) }
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

    // MARK: Header and status

    private var missionHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mission Queue")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(summary.open == 0 ? "The board is clear. Suspiciously efficient." : "Prioritised work across every active operation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if summary.overdue > 0 || summary.blocked > 0 {
                Label("\(summary.overdue + summary.blocked) need attention", systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
            Button { showingNewTask = true } label: {
                Label("New Mission", systemImage: "plus")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.cyan)
        }
    }

    private var statusRail: some View {
        HStack(spacing: 0) {
            TaskMetric(title: "Open", value: "\(summary.open)", tint: .primary)
            TaskMetricDivider()
            TaskMetric(title: "Due today", value: "\(summary.today)", tint: summary.today > 0 ? .cyan : .secondary)
            TaskMetricDivider()
            TaskMetric(title: "Overdue", value: "\(summary.overdue)", tint: summary.overdue > 0 ? .red : .secondary)
            TaskMetricDivider()
            TaskMetric(title: "Blocked", value: "\(summary.blocked)", tint: summary.blocked > 0 ? .orange : .secondary)
            TaskMetricDivider()
            TaskMetric(title: "Completed", value: "\(summary.completed)", tint: .green)
            TaskMetricDivider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(completionPercentage, format: .percent.precision(.fractionLength(0)))
                        .font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(.green)
                    Text("momentum").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: completionPercentage).tint(.green).controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 18)
        .taskSurface(cornerRadius: 16)
    }

    // MARK: Priority now

    @ViewBuilder
    private var focusPanel: some View {
        if let task = focusTask {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Priority now", systemImage: "scope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.cyan)
                    Spacer()
                    PriorityChip(priority: task.priority)
                }
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(task.title)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)
                        if !task.notes.isEmpty {
                            Text(task.notes).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                        TaskMetaChips(task: task, projectName: projectName(for: task))
                    }
                    Spacer(minLength: 20)
                    HStack(spacing: 10) {
                        Button { taskBeingEdited = task } label: {
                            Label("Edit", systemImage: "pencil").padding(.horizontal, 4)
                        }
                        .controlSize(.large)
                        Button { TaskStore.setCompleted(task, true) } label: {
                            Label("Mark Complete", systemImage: "checkmark").fontWeight(.semibold).padding(.horizontal, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                    }
                }
            }
            .padding(24)
            .taskSurface(cornerRadius: 18, highlighted: true)
        } else {
            HStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("No active mission").font(.title3.weight(.semibold))
                    Text("Everything is either complete or waiting for your next instruction.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .taskSurface(cornerRadius: 18, highlighted: true)
        }
    }

    // MARK: Queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(TaskQueueScope.allCases) { scope in
                    ScopeChip(scope: scope, count: count(for: scope), isSelected: selectedScope == scope) {
                        selectedScope = scope
                    }
                }
                Spacer(minLength: 12)
                Picker("Project", selection: $selectedProjectID) {
                    Text("All projects").tag(UUID?.none)
                    ForEach(activeProjects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if visibleTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: searchText.isEmpty ? selectedScope.systemImage : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(searchText.isEmpty ? "Nothing in this queue" : "No matching missions")
                        .font(.headline)
                    Text(searchText.isEmpty ? emptyQueueMessage : "Try a broader search or another filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
                .taskSurface(cornerRadius: 16)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleTasks) { task in
                        MissionTaskCard(
                            task: task,
                            projectName: projectName(for: task),
                            onEdit: { taskBeingEdited = task },
                            onDelete: { taskPendingDeletion = task }
                        )
                    }
                }
            }
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
}

// MARK: - Queue pieces

private struct ScopeChip: View {
    let scope: TaskQueueScope
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

/// One task in the queue. The whole card opens the editor on a single click; the circle completes it.
private struct MissionTaskCard: View {
    @Bindable var task: TaskItem
    let projectName: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button { TaskStore.setCompleted(task, !task.isCompleted) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(task.isCompleted ? Color.green : priorityColor(task.priority))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Reopen" : "Mark complete")
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text(task.title)
                    .font(.system(size: 16, weight: .semibold))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Color.secondary : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                TaskMetaChips(task: task, projectName: projectName)
            }

            Spacer(minLength: 16)

            HStack(spacing: 6) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                .controlSize(.regular)
                Menu {
                    Button("Edit…", systemImage: "pencil", action: onEdit)
                    Button(task.isCompleted ? "Reopen" : "Mark Complete",
                           systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark") {
                        TaskStore.setCompleted(task, !task.isCompleted)
                    }
                    if !task.isCompleted {
                        Button(task.isBlocked ? "Unblock" : "Mark as Blocked",
                               systemImage: task.isBlocked ? "hand.thumbsup" : "hand.raised") {
                            task.isBlocked.toggle()
                            if !task.isBlocked { task.blockedReason = "" }
                        }
                    }
                    Divider()
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
                .stroke(isHovering ? Color.cyan.opacity(0.45) : Color.white.opacity(0.07), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            // Priority accent along the card's left edge.
            RoundedRectangle(cornerRadius: 2)
                .fill(task.isCompleted ? Color.green.opacity(0.5) : priorityColor(task.priority))
                .frame(width: 3)
                .padding(.vertical, 14)
        }
        .opacity(task.isCompleted ? 0.72 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onEdit)
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        // Completing a task from the Open queue removes its card while the pointer is still on it.
        .onDisappear { if isHovering { NSCursor.pop() } }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Click to edit")
        .contextMenu {
            Button("Edit…", systemImage: "pencil", action: onEdit)
            Button(task.isBlocked ? "Unblock Task" : "Mark as Blocked", systemImage: task.isBlocked ? "hand.thumbsup" : "hand.raised") {
                task.isBlocked.toggle()
                if !task.isBlocked { task.blockedReason = "" }
            }
            Divider()
            Button("Delete Task", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

/// Project, due date, priority, and blocked state as small chips.
private struct TaskMetaChips: View {
    let task: TaskItem
    let projectName: String?

    var body: some View {
        HStack(spacing: 8) {
            MetaChip(text: projectName ?? "Inbox", systemImage: projectName == nil ? "tray" : "square.stack.3d.up", tint: .secondary)
            if let dueDate = task.dueDate {
                let overdue = dueDate < .now && !task.isCompleted
                MetaChip(text: dueText(dueDate, overdue: overdue),
                         systemImage: overdue ? "clock.badge.exclamationmark" : "calendar",
                         tint: overdue ? .red : (Calendar.current.isDateInToday(dueDate) ? .cyan : .secondary))
            } else {
                MetaChip(text: "No deadline", systemImage: "calendar", tint: .secondary.opacity(0.7))
            }
            PriorityChip(priority: task.priority)
            if task.isBlocked && !task.isCompleted {
                MetaChip(text: task.blockedReason.isEmpty ? "Blocked" : "Blocked: \(task.blockedReason)",
                         systemImage: "hand.raised.fill", tint: .orange)
            }
        }
    }

    private func dueText(_ date: Date, overdue: Bool) -> String {
        let calendar = Calendar.current
        let day = date.formatted(.dateTime.day().month(.abbreviated))
        if calendar.isDateInToday(date) { return "Today, \(date.formatted(date: .omitted, time: .shortened))" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow, \(date.formatted(date: .omitted, time: .shortened))" }
        if overdue { return "Overdue · \(day)" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)).day ?? 0
        if days < 7 { return "In \(days) days · \(day)" }
        let year = calendar.component(.year, from: date) == calendar.component(.year, from: .now) ? "" : " \(calendar.component(.year, from: date))"
        return "Due \(day)\(year)"
    }
}

private struct MetaChip: View {
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

private struct PriorityChip: View {
    let priority: TaskPriority

    var body: some View {
        Text(priority.title.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.7)
            .foregroundStyle(priorityColor(priority))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(priorityColor(priority).opacity(0.14), in: Capsule())
    }
}

private func priorityColor(_ priority: TaskPriority) -> Color {
    switch priority {
    case .low: .secondary
    case .normal: .cyan
    case .high: .orange
    case .critical: .red
    }
}

private struct TaskMetric: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.monospacedDigit().weight(.bold)).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

private struct TaskMetricDivider: View {
    var body: some View { Divider().frame(height: 38) }
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

/// Creates a task, or edits one when opened with `editing:`.
struct TaskEditorView: View {
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
    private let task: TaskItem?

    init(projectID: UUID? = nil) {
        task = nil
        _projectID = State(initialValue: projectID)
    }

    init(editing task: TaskItem) {
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate = State(initialValue: task.dueDate ?? Date.now.addingTimeInterval(3_600))
        _priority = State(initialValue: task.priority)
        _projectID = State(initialValue: task.projectID)
        _isBlocked = State(initialValue: task.isBlocked)
        _blockedReason = State(initialValue: task.blockedReason)
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
                        // An archived project stays listed while it is this task's project.
                        ForEach(projects.filter { !$0.isArchived || $0.id == projectID }) { project in
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
            .navigationTitle(task == nil ? "New Mission" : "Edit Mission")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(task == nil ? "Add Mission" : "Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 500, height: 500)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReason = blockedReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if let task {
            TaskStore.update(task, title: cleanTitle, notes: notes, dueDate: hasDueDate ? dueDate : nil,
                             priority: priority, projectID: projectID, isBlocked: isBlocked, blockedReason: cleanReason)
        } else {
            TaskStore.add(TaskItem(title: cleanTitle, notes: notes, dueDate: hasDueDate ? dueDate : nil,
                                   priority: priority, projectID: projectID, isBlocked: isBlocked,
                                   blockedReason: cleanReason), to: modelContext)
        }
        dismiss()
    }
}
