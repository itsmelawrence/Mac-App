import Foundation
import SwiftData

/// Task changes that have side effects beyond the model. Views call these instead of
/// mutating tasks directly, so reminders always follow the task's state.
@MainActor
enum TaskStore {
    static func add(_ task: TaskItem, to context: ModelContext, reminders: TaskReminderScheduling = NotificationService()) {
        context.insert(task)
        schedule(task, reminders)
    }

    static func setCompleted(_ task: TaskItem, _ completed: Bool, reminders: TaskReminderScheduling = NotificationService()) {
        task.isCompleted = completed
        if completed {
            cancel(task, reminders)
        } else {
            schedule(task, reminders)
        }
    }

    static func delete(_ task: TaskItem, from context: ModelContext, reminders: TaskReminderScheduling = NotificationService()) {
        cancel(task, reminders)
        context.delete(task)
    }

    /// The reminder an open task with a future due date should have.
    static func reminder(for task: TaskItem, now: Date = .now) -> TaskReminder? {
        guard !task.isCompleted, let dueDate = task.dueDate, dueDate > now else { return nil }
        return TaskReminder(taskID: task.id, title: task.title, dueDate: dueDate)
    }

    private static func schedule(_ task: TaskItem, _ reminders: TaskReminderScheduling) {
        guard let reminder = reminder(for: task) else { return }
        Task { try? await reminders.schedule(reminder) }
    }

    private static func cancel(_ task: TaskItem, _ reminders: TaskReminderScheduling) {
        // Reminders from before 0.2.25 were keyed by the persistent model ID.
        reminders.cancel(identifiers: [TaskReminder.identifier(for: task.id), "task-\(task.persistentModelID)"])
    }
}
