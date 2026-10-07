import Foundation
import Testing
@testable import JarvisDashboard

struct BriefingComposerTests {
    @Test func prioritisesOverdueTasks() {
        let output = BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: 4,
                overdueTaskCount: 2,
                activeProjectCount: 1,
                weather: nil,
                significantEarthquakeCount: 0
            ),
            date: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(output.contains("2 overdue tasks"))
        #expect(!output.contains("4 pending tasks"))
        #expect(output.contains("1 active project"))
    }

    @Test func producesClearQueueMessage() {
        let output = BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: 0,
                overdueTaskCount: 0,
                activeProjectCount: 0,
                weather: nil,
                significantEarthquakeCount: 0
            )
        )

        #expect(output.contains("task queue is clear"))
    }
}
