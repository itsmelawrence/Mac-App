import Foundation
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
        monitoringAvailable: true,
        priorityTask: "Review JAK proposal",
        blockedTaskNames: ["Await client assets"],
        waitingProjectNames: ["Skeema Digital Co."],
        unhealthySiteNames: ["JAK Pest Control Services"],
        weatherReport: "In Manila, it is 28°C and partly cloudy. Rain probability is 20%.",
        projects: [JarvisProjectBrief(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "JAK Pest Control Services",
            client: "JAK Pest Control",
            status: "Active",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            nextAction: "Review mobile menu",
            openTasks: 2,
            overdueTasks: 1,
            blockedTasks: 1,
            siteHealth: "Up",
            siteCheckedAt: Date(timeIntervalSince1970: 1_700_000_000),
            monitoringSource: "JARVIS site checks"
        )]
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
            monitoredSites: 2, unhealthySites: 0, unverifiedSites: 2, monitoringAvailable: false,
            priorityTask: nil, blockedTaskNames: [], waitingProjectNames: [], unhealthySiteNames: [], weatherReport: nil,
            projects: []
        )
        let result = JarvisCommandEngine.execute("Are my sites healthy?", context: unavailable)
        #expect(result.response.contains("cannot confirm"))
        #expect(result.destination == nil)
    }

    @Test func allSitesUpIsReportedOnlyWhenNothingNeedsAttention() {
        let healthy = JarvisCommandContext(
            briefing: "Ready", pendingTasks: 0, overdueTasks: 0, activeProjects: 1,
            monitoredSites: 2, unhealthySites: 0, unverifiedSites: 0, monitoringAvailable: true,
            priorityTask: nil, blockedTaskNames: [], waitingProjectNames: [], unhealthySiteNames: [], weatherReport: nil,
            projects: []
        )
        #expect(JarvisCommandEngine.execute("Are my sites healthy?", context: healthy).response == "All 2 monitored websites are up.")
    }

    @Test func unknownCommandExplainsCurrentCapabilities() {
        let result = JarvisCommandEngine.execute("Calculate orbital mechanics", context: context)
        #expect(result.destination == nil)
        #expect(!result.shouldSpeak)
        #expect(result.response.contains("Say “help”"))
        #expect(!result.understood)
    }

    @Test func builtInCommandsAreUnderstoodSoTheyNeverReachTheModel() {
        for command in ["Brief me", "What needs attention?", "How is JAK?", "How is Orbital Dynamics?", "Open settings"] {
            #expect(JarvisCommandEngine.execute(command, context: context).understood, "\(command)")
        }
    }

    @Test func namedProjectQuestionReturnsSourcedCard() {
        let result = JarvisCommandEngine.execute("How is JAK?", context: context)
        #expect(result.card?.title == "JAK Pest Control Services")
        #expect(result.card?.facts.contains("Next action: Review mobile menu") == true)
        #expect(result.card?.facts.contains("Tasks: 2 open, 1 overdue, 1 blocked") == true)
        #expect(result.card?.source.contains("JARVIS site checks") == true)
        #expect(result.card?.projectID == context.projects[0].id)
        #expect(result.destination == nil)
    }

    @Test func unknownProjectQuestionDoesNotInventAnAnswer() {
        let result = JarvisCommandEngine.execute("How is Orbital Dynamics?", context: context)
        #expect(result.card == nil)
        #expect(result.response.contains("could not match"))
    }

    @Test func ambiguousProjectNameRequiresClarification() {
        let second = JarvisProjectBrief(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "JAK Booking Portal", client: "", status: "Active",
            updatedAt: .now, nextAction: "", openTasks: 0, overdueTasks: 0, blockedTasks: 0,
            siteHealth: "No website", siteCheckedAt: nil, monitoringSource: "no website"
        )
        let ambiguous = JarvisCommandContext(
            briefing: context.briefing, pendingTasks: context.pendingTasks, overdueTasks: context.overdueTasks,
            activeProjects: context.activeProjects, monitoredSites: context.monitoredSites, unhealthySites: context.unhealthySites,
            unverifiedSites: context.unverifiedSites,
            monitoringAvailable: context.monitoringAvailable, priorityTask: context.priorityTask,
            blockedTaskNames: context.blockedTaskNames, waitingProjectNames: context.waitingProjectNames,
            unhealthySiteNames: context.unhealthySiteNames, weatherReport: context.weatherReport,
            projects: context.projects + [second]
        )
        let result = JarvisCommandEngine.execute("How is JAK?", context: ambiguous)
        #expect(result.card == nil)
        #expect(result.response.contains("more than one"))
    }
}
