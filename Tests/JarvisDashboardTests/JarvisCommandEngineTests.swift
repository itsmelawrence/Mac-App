import Testing
@testable import JarvisDashboard

struct JarvisCommandEngineTests {
    private let context = JarvisCommandContext(
        briefing: "All systems are nominal.",
        pendingTasks: 6,
        overdueTasks: 2,
        activeProjects: 3,
        monitoredSites: 3,
        unhealthySites: 1
    )

    @Test func briefingCommandReturnsSpokenBriefing() {
        let result = JarvisCommandEngine.execute("Give me a situation report", context: context)
        #expect(result.response == context.briefing)
        #expect(result.destination == .today)
        #expect(result.shouldSpeak)
    }

    @Test func taskCommandRoutesToTasksWithCounts() {
        let result = JarvisCommandEngine.execute("Show overdue tasks", context: context)
        #expect(result.destination == .tasks)
        #expect(result.response.contains("6 open tasks"))
        #expect(result.response.contains("2 overdue"))
    }

    @Test func monitoringCommandRoutesToProjectsWithHealth() {
        let result = JarvisCommandEngine.execute("How are my websites?", context: context)
        #expect(result.destination == .projects)
        #expect(result.response.contains("1 of 3"))
    }

    @Test func unknownCommandExplainsCurrentCapabilities() {
        let result = JarvisCommandEngine.execute("Calculate orbital mechanics", context: context)
        #expect(result.destination == nil)
        #expect(!result.shouldSpeak)
        #expect(result.response.contains("next system upgrade"))
    }
}
