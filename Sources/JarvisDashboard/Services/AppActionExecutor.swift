import Foundation
import SwiftData

/// Performs, and reverses, the assistant's app actions on JARVIS's own data, after the vault tools'
/// action gate has validated (and for Tier 2, you have approved) them. Tasks change only through
/// `TaskStore`, so reminders follow, exactly as when you act in the app.
@MainActor
enum AppActionExecutor {
    struct Failure: Error, Equatable {
        let reason: String
    }

    static func perform(_ action: String, args: [String: String?], context: ModelContext,
                        calendar: Calendar = .current,
                        reminders: TaskReminderScheduling = NotificationService()) -> Result<[String: String], Failure> {
        switch action {
        case "task_add":
            guard let title = args["title"] ?? nil, !title.isEmpty else { return .failure(Failure(reason: "the task has no title")) }
            var projectID: UUID?
            if let raw = args["project_id"] ?? nil {
                guard let id = UUID(uuidString: raw), project(id, in: context) != nil else {
                    return .failure(Failure(reason: "that project no longer exists"))
                }
                projectID = id
            }
            var due: Date?
            if let raw = args["due"] ?? nil {
                guard let date = dueDate(raw, calendar: calendar) else { return .failure(Failure(reason: "the due date can't be read: \(raw)")) }
                due = date
            }
            let task = TaskItem(title: title, notes: (args["notes"] ?? nil) ?? "", dueDate: due,
                                priority: priority(args["priority"] ?? nil), projectID: projectID)
            TaskStore.add(task, to: context, reminders: reminders)
            try? context.save()
            return .success(["task_id": task.id.uuidString, "title": title])
        case "task_complete":
            guard let raw = args["task_id"] ?? nil, let id = UUID(uuidString: raw), let task = task(id, in: context) else {
                return .failure(Failure(reason: "that task no longer exists"))
            }
            guard !task.isCompleted else { return .failure(Failure(reason: "the task is already complete")) }
            TaskStore.setCompleted(task, true, reminders: reminders)
            try? context.save()
            return .success(["task_id": raw, "title": task.title])
        default:
            return .failure(Failure(reason: "JARVIS doesn't know the action \(action)"))
        }
    }

    /// Undoes an app action, only while the task is as that action left it.
    static func reverse(_ action: String, result: [String: String], context: ModelContext,
                        reminders: TaskReminderScheduling = NotificationService()) -> Result<Void, Failure> {
        guard let raw = result["task_id"], let id = UUID(uuidString: raw), let task = task(id, in: context) else {
            return .failure(Failure(reason: "the task no longer exists"))
        }
        switch action {
        case "task_add":
            guard task.title == result["title"] else { return .failure(Failure(reason: "the task was edited since; delete it by hand")) }
            TaskStore.delete(task, from: context, reminders: reminders)
        case "task_complete":
            guard task.isCompleted else { return .failure(Failure(reason: "the task is already open again")) }
            TaskStore.setCompleted(task, false, reminders: reminders)
        default:
            return .failure(Failure(reason: "JARVIS can't undo \(action)"))
        }
        try? context.save()
        return .success(())
    }

    /// "2026-11-05" is 09:00 local that day; a date-time with a zone is exact; without one, local time.
    static func dueDate(_ text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        if text.count == 10, parts.count == 3 {
            return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 9))
        }
        let zoned = ISO8601DateFormatter()
        if let date = zoned.date(from: text) { return date }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = calendar.timeZone
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: text) { return date }
        }
        return nil
    }

    private static func priority(_ text: String?) -> TaskPriority {
        switch text {
        case "low": .low
        case "high": .high
        case "critical": .critical
        default: .normal
        }
    }

    private static func task(_ id: UUID, in context: ModelContext) -> TaskItem? {
        try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })).first
    }

    private static func project(_ id: UUID, in context: ModelContext) -> ProjectItem? {
        try? context.fetch(FetchDescriptor<ProjectItem>(predicate: #Predicate { $0.id == id })).first
    }
}
