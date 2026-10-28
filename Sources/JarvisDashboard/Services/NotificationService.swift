import Foundation
import UserNotifications

/// A reminder as plain values, so no SwiftData model crosses actors when it is scheduled.
struct TaskReminder: Equatable, Sendable {
    let taskID: UUID
    let title: String
    let dueDate: Date

    var identifier: String { Self.identifier(for: taskID) }
    static func identifier(for taskID: UUID) -> String { "task-\(taskID.uuidString)" }
}

protocol TaskReminderScheduling: Sendable {
    func schedule(_ reminder: TaskReminder) async throws
    func cancel(identifiers: [String])
}

struct NotificationService: TaskReminderScheduling {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }

    func schedule(_ reminder: TaskReminder) async throws {
        guard reminder.dueDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task due"
        content.body = reminder.title
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }

    func cancel(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
