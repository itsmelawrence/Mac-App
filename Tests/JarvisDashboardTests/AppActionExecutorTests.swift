import Foundation
import SwiftData
import Testing
@testable import JarvisDashboard

@MainActor
struct AppActionExecutorTests {
    private func context() throws -> ModelContext {
        let configuration = ModelConfiguration(schema: JarvisDataStore.schema, isStoredInMemoryOnly: true)
        return ModelContext(try JarvisDataStore.makeContainer(configuration: configuration))
    }

    private let recorder = ReminderRecorder()

    private func reason<T>(_ result: Result<T, AppActionExecutor.Failure>) -> String? {
        if case let .failure(failure) = result { return failure.reason }
        return nil
    }

    @Test func addsATaskWithItsProjectAndDueDateAndUndoRemovesIt() throws {
        let context = try context()
        let project = ProjectItem(name: "Clinic")
        context.insert(project)
        let calendar = Calendar(identifier: .gregorian)
        let result = try AppActionExecutor.perform("task_add", args: [
            "title": "Call Bob", "notes": "About the quote", "priority": "critical", "due": "2026-11-05",
            "project_id": project.id.uuidString,
        ], context: context, calendar: calendar, reminders: recorder).get()

        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first)
        #expect(result == ["task_id": task.id.uuidString, "title": "Call Bob"])
        #expect(task.projectID == project.id && task.priority == .critical && task.notes == "About the quote")
        #expect(task.dueDate == calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))

        try AppActionExecutor.reverse("task_add", result: result, context: context, reminders: recorder).get()
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).isEmpty)
    }

    @Test func completesATaskOnceAndUndoReopensIt() throws {
        let context = try context()
        let task = TaskItem(title: "Send invoice")
        context.insert(task)
        let result = try AppActionExecutor.perform("task_complete", args: ["task_id": task.id.uuidString], context: context, reminders: recorder).get()
        #expect(task.isCompleted)
        #expect(reason(AppActionExecutor.perform("task_complete", args: ["task_id": task.id.uuidString], context: context, reminders: recorder)) == "the task is already complete")
        try AppActionExecutor.reverse("task_complete", result: result, context: context, reminders: recorder).get()
        #expect(!task.isCompleted)
    }

    @Test func refusesWhatNoLongerMatches() throws {
        let context = try context()
        #expect(reason(AppActionExecutor.perform("task_add", args: ["title": "x", "project_id": UUID().uuidString], context: context, reminders: recorder)) == "that project no longer exists")
        #expect(reason(AppActionExecutor.perform("task_complete", args: ["task_id": UUID().uuidString], context: context, reminders: recorder)) == "that task no longer exists")
        let result = try AppActionExecutor.perform("task_add", args: ["title": "Original"], context: context, reminders: recorder).get()
        try #require(try context.fetch(FetchDescriptor<TaskItem>()).first).title = "Edited by hand"
        #expect(reason(AppActionExecutor.reverse("task_add", result: result, context: context, reminders: recorder)) == "the task was edited since; delete it by hand")
        #expect(reason(AppActionExecutor.perform("delete_everything", args: [:], context: context, reminders: recorder)) == "JARVIS doesn't know the action delete_everything")
    }

    @Test func readsDueDatesAsDatesZonedTimesAndLocalTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
        #expect(AppActionExecutor.dueDate("2026-11-05T14:00:00Z", calendar: calendar)
                == ISO8601DateFormatter().date(from: "2026-11-05T14:00:00Z"))
        #expect(AppActionExecutor.dueDate("2026-11-05T14:00", calendar: calendar)
                == ISO8601DateFormatter().date(from: "2026-11-05T06:00:00Z"))
        #expect(AppActionExecutor.dueDate("next tuesday", calendar: calendar) == nil)
    }
}
