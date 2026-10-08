import SwiftData
import SwiftUI

struct TasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \ProjectItem.name) private var projects: [ProjectItem]

    @State private var showingNewTask = false
    @State private var searchText = ""

    private var filteredTasks: [TaskItem] {
        guard !searchText.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No tasks yet" : "No matching tasks",
                    systemImage: "checklist",
                    description: Text(searchText.isEmpty ? "Add your first next action." : "Try another search term.")
                )
            } else {
                List {
                    ForEach(filteredTasks) { task in
                        TaskListRow(task: task, projectName: projects.first { $0.id == task.projectID }?.name)
                    }
                    .onDelete(perform: deleteTasks)
                }
            }
        }
        .navigationTitle("Tasks")
        .searchable(text: $searchText)
        .toolbar {
            Button { showingNewTask = true } label: {
                Label("New task", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewTask) {
            NewTaskView()
        }
    }

    private func deleteTasks(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(filteredTasks[index]) }
    }
}

private struct TaskListRow: View {
    @Bindable var task: TaskItem
    let projectName: String?

    var body: some View {
        HStack(spacing: 12) {
            Button { task.isCompleted.toggle() } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.isCompleted)
                if !task.notes.isEmpty {
                    Text(task.notes).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 8) {
                    if let projectName {
                        Label(projectName, systemImage: "square.stack.3d.up")
                    }
                    if task.isBlocked {
                        Label(task.blockedReason.isEmpty ? "Blocked" : task.blockedReason, systemImage: "hand.raised.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let dueDate = task.dueDate {
                Text(dueDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(!task.isCompleted && dueDate < .now ? .red : .secondary)
            }
            Text(task.priority.title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 5)
        .contextMenu {
            Button(task.isBlocked ? "Unblock Task" : "Mark as Blocked") {
                task.isBlocked.toggle()
                if !task.isBlocked { task.blockedReason = "" }
            }
        }
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
                TextField("Task", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                Picker("Priority", selection: $priority) {
                    ForEach(TaskPriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }
                Picker("Project", selection: $projectID) {
                    Text("Inbox / No project").tag(UUID?.none)
                    ForEach(projects.filter { !$0.isArchived }) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                Toggle("Blocked", isOn: $isBlocked)
                if isBlocked {
                    TextField("What is blocking this task?", text: $blockedReason)
                }
                Toggle("Set due date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate)
                }
            }
            .padding(20)
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let task = TaskItem(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            notes: notes,
                            dueDate: hasDueDate ? dueDate : nil,
                            priority: priority,
                            projectID: projectID,
                            isBlocked: isBlocked,
                            blockedReason: blockedReason.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        modelContext.insert(task)
                        if hasDueDate {
                            Task { try? await NotificationService().scheduleReminder(for: task) }
                        }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 480, height: 400)
    }
}
