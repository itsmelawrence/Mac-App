import SwiftData
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<TaskItem> { !$0.isCompleted }) private var pendingTasks: [TaskItem]

    @State private var quickTaskTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("JARVIS").font(.headline)
                    Text("\(pendingTasks.count) pending tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .foregroundStyle(.cyan)
            }

            HStack {
                TextField("Quick task", text: $quickTaskTitle)
                    .onSubmit(addQuickTask)
                Button(action: addQuickTask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(quickTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Divider()

            Button("Open Command Centre") { openWindow(id: "dashboard") }
            Button("Present Briefing") { appState.requestBriefing() }
            Divider()
            Button("Quit JARVIS") { NSApplication.shared.terminate(nil) }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func addQuickTask() {
        let cleanTitle = quickTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        modelContext.insert(TaskItem(title: cleanTitle))
        quickTaskTitle = ""
    }
}
