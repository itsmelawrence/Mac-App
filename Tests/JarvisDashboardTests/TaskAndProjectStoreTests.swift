import Foundation
import SwiftData
import Testing
@testable import JarvisDashboard

/// Records reminder calls instead of touching the notification centre.
final class ReminderRecorder: TaskReminderScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var scheduled: [TaskReminder] = []
    private(set) var cancelled: [String] = []

    func schedule(_ reminder: TaskReminder) async throws { lock.withLock { scheduled.append(reminder) } }
    func cancel(identifiers: [String]) { lock.withLock { cancelled += identifiers } }
}

@MainActor
struct TaskAndProjectStoreTests {
    private func context() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: JarvisDataStore.schema, isStoredInMemoryOnly: true)
        return ModelContext(try JarvisDataStore.makeContainer(configuration: configuration))
    }

    @Test func remindersFollowTaskLifecycle() async throws {
        let context = try context()
        let recorder = ReminderRecorder()
        let task = TaskItem(title: "Send invoice", dueDate: .now.addingTimeInterval(3_600))

        TaskStore.add(task, to: context, reminders: recorder)
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.scheduled.map(\.taskID) == [task.id])

        TaskStore.setCompleted(task, true, reminders: recorder)
        #expect(task.isCompleted)
        #expect(recorder.cancelled.contains(TaskReminder.identifier(for: task.id)))

        TaskStore.setCompleted(task, false, reminders: recorder)
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.scheduled.count == 2)

        TaskStore.delete(task, from: context, reminders: recorder)
        #expect(recorder.cancelled.filter { $0 == TaskReminder.identifier(for: task.id) }.count == 2)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    }

    @Test func noReminderForPastOrUndatedOrCompletedTasks() {
        #expect(TaskStore.reminder(for: TaskItem(title: "No date")) == nil)
        #expect(TaskStore.reminder(for: TaskItem(title: "Past", dueDate: .now.addingTimeInterval(-60))) == nil)
        #expect(TaskStore.reminder(for: TaskItem(title: "Done", dueDate: .now.addingTimeInterval(60), isCompleted: true)) == nil)
    }

    @Test func deletingProjectMovesTasksToInboxAndKeepsBackupsRestorable() throws {
        let context = try context()
        let project = ProjectItem(name: "Client site")
        context.insert(project)
        let linked = TaskItem(title: "Linked", projectID: project.id)
        let other = TaskItem(title: "Other")
        context.insert(linked)
        context.insert(other)
        try context.save()

        var deletedCredentials: [UUID] = []
        try ProjectStore.delete(project, from: context) { deletedCredentials.append($0) }

        #expect(try context.fetch(FetchDescriptor<ProjectItem>()).isEmpty)
        #expect(linked.projectID == nil)
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).count == 2)
        #expect(deletedCredentials == [project.id])

        // The bug this fixes: a backup taken now must import into a store that lacks the project.
        let service = JarvisBackupService(defaults: UserDefaults(suiteName: "store-test-\(UUID().uuidString)")!)
        let document = try service.makeDocument(context: context)
        #expect(try service.preview(document, context: try self.context()).tasks.new == 2)
    }

    @Test func deletingProjectDirectlyStillBreaksBackups() throws {
        // Documents the defect ProjectStore prevents: a raw delete leaves a dangling projectID.
        let context = try context()
        let project = ProjectItem(name: "Client site")
        context.insert(project)
        context.insert(TaskItem(title: "Linked", projectID: project.id))
        try context.save()
        context.delete(project)
        try context.save()

        let service = JarvisBackupService(defaults: UserDefaults(suiteName: "store-test-\(UUID().uuidString)")!)
        let document = try service.makeDocument(context: context)
        #expect(throws: JarvisBackupError.self) { try service.preview(document, context: try self.context()) }
    }

    @Test func credentialFailureDoesNotUndoDeletion() throws {
        let context = try context()
        let project = ProjectItem(name: "Old site")
        context.insert(project)
        try context.save()
        struct KeychainDown: Error {}
        try ProjectStore.delete(project, from: context) { _ in throw KeychainDown() }
        #expect(try context.fetch(FetchDescriptor<ProjectItem>()).isEmpty)
    }
}
