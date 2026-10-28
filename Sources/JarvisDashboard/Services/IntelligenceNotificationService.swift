import Foundation
import UserNotifications

struct IntelligenceNotificationService: Sendable {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func deliverNewCriticalAlerts(
        _ alerts: [IntelligenceAlert],
        quietStartHour: Int,
        quietEndHour: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async {
        guard !Self.isQuietHour(
            calendar.component(.hour, from: now),
            start: quietStartHour,
            end: quietEndHour
        ) else { return }

        let memory = RecentAlertIDs(key: "intelligence.notifiedAlertIDs")
        let delivered = Set(memory.load())
        let candidates = alerts.filter { $0.severity >= .warning && !delivered.contains($0.id) }

        var sent: [String] = []
        for alert in candidates.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body = alert.detail
            content.sound = .default
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            sent.append(alert.id)
        }
        memory.remember(sent)
    }

    static func isQuietHour(_ hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end { return (start..<end).contains(hour) }
        return hour >= start || hour < end
    }
}
