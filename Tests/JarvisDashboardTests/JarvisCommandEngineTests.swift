import Testing
@testable import JarvisDashboard

struct JarvisCommandEngineTests {
    private let context = JarvisCommandContext(
        briefing: "All systems are nominal.",
        pendingTasks: 6,
        overdueTasks: 2,
        activeProjects: 3,
        monitoredSites: 3,
        unhealthySites: 1,
        unverifiedSites: 1,
        maintenanceSites: 0,
        monitoringAvailable: true,
        priorityTask: "Review JAK proposal",
        blockedTaskNames: ["Await client assets"],
        waitingProjectNames: ["Skeema Digital Co."],
        unhealthySiteNames: ["JAK Pest Control Services"],
        weatherReport: "In Manila, it is 28°C and partly cloudy. Rain probability is 20%."
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

    @Test func monitoringCommandReportsHealthWithoutLeavingConsole() {
        let result = JarvisCommandEngine.execute("How are my websites?", context: context)
        #expect(result.destination == nil)
        #expect(result.response.contains("JAK Pest Control Services"))
        #expect(result.response.contains("awaiting checks"))
    }

    @Test func attentionCommandSummarisesOperationalIssues() {
        let result = JarvisCommandEngine.execute("What needs attention?", context: context)
        #expect(result.response.contains("1 monitored site"))
        #expect(result.response.contains("2 overdue tasks"))
        #expect(result.response.contains("1 blocked task"))
        #expect(result.response.contains("1 project waiting"))
    }

    @Test func nextActionUsesTaskName() {
        let result = JarvisCommandEngine.execute("What should I work on?", context: context)
        #expect(result.destination == nil)
        #expect(result.response.contains("Review JAK proposal"))
    }

    @Test func blockedAndWaitingCommandsNameItems() {
        #expect(JarvisCommandEngine.execute("Show blockers", context: context).response.contains("Await client assets"))
        #expect(JarvisCommandEngine.execute("Which clients are waiting?", context: context).response.contains("Skeema Digital Co."))
    }

    @Test func weatherCommandReturnsObservedWeather() {
        let result = JarvisCommandEngine.execute("What's the weather?", context: context)
        #expect(result.response.contains("28°C"))
        #expect(result.destination == nil)
    }

    @Test func monitoringUnavailableIsNeverReportedHealthy() {
        let unavailable = JarvisCommandContext(
            briefing: "Ready", pendingTasks: 0, overdueTasks: 0, activeProjects: 1,
            monitoredSites: 2, unhealthySites: 0, unverifiedSites: 2, maintenanceSites: 0, monitoringAvailable: false,
            priorityTask: nil, blockedTaskNames: [], waitingProjectNames: [], unhealthySiteNames: [], weatherReport: nil
        )
        let result = JarvisCommandEngine.execute("Are my sites healthy?", context: unavailable)
        #expect(result.response.contains("cannot confirm"))
        #expect(result.destination == nil)
    }

    @Test func maintenanceIsNotReportedHealthy() {
        let maintenance = JarvisCommandContext(
            briefing: "Ready", pendingTasks: 0, overdueTasks: 0, activeProjects: 1,
            monitoredSites: 1, unhealthySites: 0, unverifiedSites: 0, maintenanceSites: 1, monitoringAvailable: true,
            priorityTask: nil, blockedTaskNames: [], waitingProjectNames: [], unhealthySiteNames: [], weatherReport: nil
        )
        let result = JarvisCommandEngine.execute("Are my sites healthy?", context: maintenance)
        #expect(result.response.contains("in maintenance"))
        #expect(!result.response.contains("All 1 monitored websites are healthy"))
    }

    @Test func unknownCommandExplainsCurrentCapabilities() {
        let result = JarvisCommandEngine.execute("Calculate orbital mechanics", context: context)
        #expect(result.destination == nil)
        #expect(!result.shouldSpeak)
        #expect(result.response.contains("Say “help”"))
    }
}
