import Foundation
import Testing
@testable import JarvisDashboard

struct TaskQueueEngineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func summarySeparatesOperationalStates() {
        let overdue = TaskItem(title: "Overdue", dueDate: now.addingTimeInterval(-60))
        let blocked = TaskItem(title: "Blocked", isBlocked: true)
        let completed = TaskItem(title: "Done", isCompleted: true)

        let summary = TaskQueueEngine.summary(for: [overdue, blocked, completed], now: now)

        #expect(summary.open == 2)
        #expect(summary.overdue == 1)
        #expect(summary.blocked == 1)
        #expect(summary.completed == 1)
    }

    @Test func focusPrefersActionableOverBlockedWork() {
        let blocked = TaskItem(title: "Critical but blocked", priority: .critical, isBlocked: true)
        let actionable = TaskItem(title: "Available", priority: .normal)

        let focus = TaskQueueEngine.focusTask(from: [blocked, actionable], now: now)

        #expect(focus?.title == "Available")
    }

    @Test func sortingPrioritisesOverdueThenPriority() {
        let futureCritical = TaskItem(title: "Future", dueDate: now.addingTimeInterval(3_600), priority: .critical)
        let overdueLow = TaskItem(title: "Overdue", dueDate: now.addingTimeInterval(-60), priority: .low)
        let overdueHigh = TaskItem(title: "Overdue high", dueDate: now.addingTimeInterval(-120), priority: .high)

        let result = TaskQueueEngine.sorted([futureCritical, overdueLow, overdueHigh], now: now)

        #expect(result.map(\.title) == ["Overdue high", "Overdue", "Future"])
    }

    @Test func todayScopeUsesCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let laterToday = TaskItem(title: "Today", dueDate: now.addingTimeInterval(60))

        #expect(TaskQueueEngine.matches(laterToday, scope: .today, now: now, calendar: calendar))
    }
}
