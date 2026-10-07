import Foundation
import SwiftData

@Model
final class TaskItem {
    var title: String
    var notes: String
    var dueDate: Date?
    var priorityRawValue: Int
    var isCompleted: Bool
    var createdAt: Date

    init(
        title: String,
        notes: String = "",
        dueDate: Date? = nil,
        priority: TaskPriority = .normal,
        isCompleted: Bool = false,
        createdAt: Date = .now
    ) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.priorityRawValue = priority.rawValue
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRawValue) ?? .normal }
        set { priorityRawValue = newValue.rawValue }
    }
}

enum TaskPriority: Int, CaseIterable, Identifiable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .critical: "Critical"
        }
    }
}
