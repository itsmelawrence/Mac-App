import SwiftData
import SwiftUI

struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectItem.updatedAt, order: .reverse) private var projects: [ProjectItem]
    @State private var showingNewProject = false

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No projects yet",
                    systemImage: "square.stack.3d.up",
                    description: Text("Create a project and give it a clear next action.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 16)], spacing: 16) {
                        ForEach(projects) { project in
                            ProjectCard(project: project) {
                                modelContext.delete(project)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            Button { showingNewProject = true } label: {
                Label("New project", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewProject) {
            NewProjectView()
        }
    }
}

private struct ProjectCard: View {
    @Bindable var project: ProjectItem
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name).font(.title3.bold())
                    if !project.client.isEmpty {
                        Text(project.client).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Delete", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            Picker("Status", selection: Binding(
                get: { project.status },
                set: { project.status = $0; project.updatedAt = .now }
            )) {
                ForEach(ProjectStatus.allCases) { status in
                    Text(status.title).tag(status)
                }
            }
            .labelsHidden()

            ProgressView(value: project.progress)
            HStack {
                Text("Progress")
                Spacer()
                Text(project.progress, format: .percent.precision(.fractionLength(0)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !project.nextAction.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT ACTION").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(project.nextAction).lineLimit(2)
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var client = ""
    @State private var summary = ""
    @State private var nextAction = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Project name", text: $name)
                TextField("Client or category", text: $client)
                TextField("Summary", text: $summary, axis: .vertical)
                    .lineLimit(3...5)
                TextField("Next action", text: $nextAction)
            }
            .padding(20)
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        modelContext.insert(ProjectItem(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            client: client,
                            summary: summary,
                            nextAction: nextAction
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(width: 500, height: 410)
    }
}
