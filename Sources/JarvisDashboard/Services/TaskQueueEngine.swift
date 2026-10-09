import Foundation

enum TaskQueueScope: String, CaseIterable, Identifiable {
    case open
    case today
    case overdue
    case blocked
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .open: "Open"
        case .today: "Today"
        case .overdue: "Overdue"
        case .blocked: "Blocked"
        case .completed: "Completed"
        }
    }

    var systemImage: String {
        switch self {
        case .open: "tray.full"
        case .today: "sun.max"
        case .overdue: "clock.badge.exclamationmark"
        case .blocked: "hand.raised.fill"
        case .completed: "checkmark.circle.fill"
        }
    }
}

struct TaskQueueSummary: Equatable {
    let open: Int
    let today: Int
    let overdue: Int
    let blocked: Int
    let completed: Int
}

enum TaskQueueEngine {
    static func summary(
        for tasks: [TaskItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TaskQueueSummary {
        TaskQueueSummary(
            open: tasks.count { !$0.isCompleted },
            today: tasks.count { task in
                guard !task.isCompleted, let dueDate = task.dueDate else { return false }
                return calendar.isDate(dueDate, inSameDayAs: now)
            },
            overdue: tasks.count { task in
                guard !task.isCompleted, let dueDate = task.dueDate else { return false }
                return dueDate < now
            },
            blocked: tasks.count { !$0.isCompleted && $0.isBlocked },
            completed: tasks.count(where: \.isCompleted)
        )
    }

    static func matches(
        _ task: TaskItem,
        scope: TaskQueueScope,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        switch scope {
        case .open:
            return !task.isCompleted
        case .today:
            guard !task.isCompleted, let dueDate = task.dueDate else { return false }
            return calendar.isDate(dueDate, inSameDayAs: now)
        case .overdue:
            guard !task.isCompleted, let dueDate = task.dueDate else { return false }
            return dueDate < now
        case .blocked:
            return !task.isCompleted && task.isBlocked
        case .completed:
            return task.isCompleted
        }
    }

    static func sorted(_ tasks: [TaskItem], now: Date = .now) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }

            let lhsOverdue = !lhs.isCompleted && (lhs.dueDate ?? .distantFuture) < now
            let rhsOverdue = !rhs.isCompleted && (rhs.dueDate ?? .distantFuture) < now
            if lhsOverdue != rhsOverdue { return lhsOverdue }

            if lhs.isBlocked != rhs.isBlocked { return !lhs.isBlocked }
            if lhs.priorityRawValue != rhs.priorityRawValue { return lhs.priorityRawValue > rhs.priorityRawValue }

            let lhsDueDate = lhs.dueDate ?? .distantFuture
            let rhsDueDate = rhs.dueDate ?? .distantFuture
            if lhsDueDate != rhsDueDate { return lhsDueDate < rhsDueDate }
            return lhs.createdAt > rhs.createdAt
        }
    }

    static func focusTask(from tasks: [TaskItem], now: Date = .now) -> TaskItem? {
        let pending = tasks.filter { !$0.isCompleted }
        let actionable = pending.filter { !$0.isBlocked }
        return sorted(actionable.isEmpty ? pending : actionable, now: now).first
    }
}
