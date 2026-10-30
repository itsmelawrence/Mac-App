import Foundation

struct JarvisCommandContext: Equatable, Sendable {
    let briefing: String
    let pendingTasks: Int
    let overdueTasks: Int
    let activeProjects: Int
    let monitoredSites: Int
    let unhealthySites: Int
    let unverifiedSites: Int
    let monitoringAvailable: Bool
    let priorityTask: String?
    let blockedTaskNames: [String]
    let waitingProjectNames: [String]
    let unhealthySiteNames: [String]
    let weatherReport: String?
    let projects: [JarvisProjectBrief]
}

struct JarvisProjectBrief: Equatable, Sendable {
    let id: UUID
    let name: String
    let client: String
    let status: String
    let updatedAt: Date
    let nextAction: String
    let openTasks: Int
    let overdueTasks: Int
    let blockedTasks: Int
    let siteHealth: String
    let siteCheckedAt: Date?
    let monitoringSource: String
}

struct JarvisResponseCard: Equatable, Sendable {
    let title: String
    let status: String
    let facts: [String]
    let source: String
    let projectID: UUID?
}

struct JarvisCommandResult: Equatable, Sendable {
    let response: String
    let destination: SidebarDestination?
    let shouldSpeak: Bool
    let card: JarvisResponseCard?
    /// False when no built-in command matched; the console then asks the local model (roadmap 4.2).
    var understood = true
}

enum JarvisCommandEngine {
    static func execute(_ command: String, context: JarvisCommandContext) -> JarvisCommandResult {
        let input = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !input.isEmpty else { return result("Awaiting your command, Sir.") }

        if contains(input, ["help", "what can you do", "commands"]) {
            return result("Try: Brief me; How is [project name]?; What needs attention?; What should I work on?; Show blocked tasks; Which clients are waiting?; Are my sites healthy?; What's the weather? You can also open Tasks, Projects, Intelligence, or Settings.")
        }
        if contains(input, ["briefing", "brief me", "status report", "situation report"]) {
            return result(context.briefing, destination: .today, speak: true)
        }
        if contains(input, ["what needs attention", "needs attention", "what's urgent", "what is urgent", "anything urgent"]) {
            var items: [String] = []
            if context.unhealthySites > 0 { items.append("\(context.unhealthySites) monitored \(plural("site", context.unhealthySites)) need attention") }
            if context.overdueTasks > 0 { items.append("\(context.overdueTasks) overdue \(plural("task", context.overdueTasks))") }
            if !context.blockedTaskNames.isEmpty { items.append("\(context.blockedTaskNames.count) blocked \(plural("task", context.blockedTaskNames.count))") }
            if !context.waitingProjectNames.isEmpty { items.append("\(context.waitingProjectNames.count) \(plural("project", context.waitingProjectNames.count)) waiting on a client") }
            if context.unverifiedSites > 0 { items.append("\(context.unverifiedSites) \(plural("site", context.unverifiedSites)) awaiting checks") }
            if context.monitoredSites > 0 && !context.monitoringAvailable { items.append("site checks have not run yet") }
            let message = items.isEmpty ? "Nothing currently requires attention in the available dashboard data." : "Attention required: \(items.joined(separator: "; "))."
            return result(message)
        }
        if contains(input, ["what should i work on", "what should i do", "next task", "next action", "my priority", "focus now"]) {
            if let task = context.priorityTask { return result("Your next actionable task is “\(task)”.") }
            if let blocked = context.blockedTaskNames.first { return result("No unblocked task is ready. “\(blocked)” is blocked; review its blocker in Tasks.") }
            return result("Your task queue is clear. No next action is recorded.")
        }
        if contains(input, ["blocked", "blockers", "stuck"]) {
            return result(namedSummary(context.blockedTaskNames, empty: "No blocked tasks are recorded.", prefix: "Blocked tasks"))
        }
        if contains(input, ["waiting on client", "waiting clients", "clients are waiting", "waiting projects"]) {
            return result(namedSummary(context.waitingProjectNames, empty: "No projects are marked waiting on a client.", prefix: "Waiting on clients"))
        }
        if contains(input, ["weather", "temperature", "rain"]) {
            return result(context.weatherReport ?? "Weather data is unavailable. Refresh Today and try again.")
        }
        if contains(input, ["site health", "sites healthy", "websites healthy", "sites down", "which sites", "how are my websites", "how are my sites", "monitoring status"]) {
            guard context.monitoredSites > 0 else { return result("No project has a website to check. Add one in Projects.") }
            guard context.monitoringAvailable else { return result("Site checks have not completed yet, so I cannot confirm whether your websites are up. Try again in a moment.") }
            var parts: [String] = []
            if !context.unhealthySiteNames.isEmpty { parts.append(namedSummary(context.unhealthySiteNames, empty: "", prefix: "Needs attention")) }
            if context.unverifiedSites > 0 { parts.append("\(context.unverifiedSites) \(plural("site", context.unverifiedSites)) awaiting checks.") }
            return result(parts.isEmpty ? "All \(context.monitoredSites) monitored websites are up." : parts.joined(separator: " "))
        }
        if let projectAnswer = projectAnswer(for: input, projects: context.projects) {
            return projectAnswer
        }
        if contains(input, ["how is ", "tell me about ", "status of ", "update on ", "what's happening with ", "what is happening with "]) {
            return result("I could not match that to a saved project. Try its full name or a distinctive word from the name.")
        }
        if contains(input, ["task", "to-do", "todo", "overdue"]) {
            let response = context.overdueTasks > 0
                ? "You have \(context.pendingTasks) open tasks, including \(context.overdueTasks) overdue. Opening the task queue."
                : "You have \(context.pendingTasks) open tasks and none are overdue. Opening the task queue."
            return result(response, destination: .tasks)
        }
        if contains(input, ["project", "client", "site", "monitoring", "website"]) {
            return result("\(context.activeProjects) projects are active. Opening operations.", destination: .projects)
        }
        if contains(input, ["news", "earthquake", "intelligence", "alert"]) {
            return result("Opening live intelligence and regional signals.", destination: .intelligence)
        }
        if contains(input, ["setting", "voice", "speech", "configure", "configuration"]) {
            return result("Opening system configuration.", destination: .settings)
        }
        if contains(input, ["today", "command centre", "command center", "home"]) {
            return result("Returning to the command centre.", destination: .today)
        }
        return result(fallbackHelp, understood: false)
    }

    static let fallbackHelp = "I can brief you, identify work needing attention, suggest your next task, report site health and weather, or open a dashboard section. Say “help” for examples."

    private static func result(
        _ response: String,
        destination: SidebarDestination? = nil,
        speak: Bool = false,
        card: JarvisResponseCard? = nil,
        understood: Bool = true
    ) -> JarvisCommandResult {
        JarvisCommandResult(response: response, destination: destination, shouldSpeak: speak, card: card, understood: understood)
    }

    private static func projectAnswer(for input: String, projects: [JarvisProjectBrief]) -> JarvisCommandResult? {
        let inputWords = Set(words(in: input))
        let candidates: [(project: JarvisProjectBrief, score: Int)] = projects.compactMap { project in
            let nameWords = meaningfulWords(in: project.name)
            let clientWords = meaningfulWords(in: project.client)
            let nameMatches = nameWords.filter { inputWords.contains($0) }.count
            let clientMatches = clientWords.filter { inputWords.contains($0) }.count
            let score = max(nameMatches, clientMatches)
            return score > 0 ? (project, score) : nil
        }
        guard let highest = candidates.map(\.score).max() else { return nil }
        let matches = candidates.filter { $0.score == highest }.map(\.project)
        guard matches.count == 1, let project = matches.first else {
            let names = matches.map(\.name).sorted().joined(separator: ", ")
            return result("I found more than one matching project: \(names). Please use a more specific name.")
        }

        let taskFact = "Tasks: \(project.openTasks) open, \(project.overdueTasks) overdue, \(project.blockedTasks) blocked"
        let siteFact = "Site: \(project.siteHealth)" + (project.siteCheckedAt.map {
            " · checked \($0.formatted(date: .abbreviated, time: .shortened))"
        } ?? "")
        let nextAction = project.nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let facts = [
            "Project: \(project.status)" + (project.client.isEmpty ? "" : " · \(project.client)"),
            siteFact,
            taskFact,
            "Next action: \(nextAction.isEmpty ? "Not recorded" : nextAction)",
            "Project updated: \(project.updatedAt.formatted(date: .abbreviated, time: .shortened))"
        ]
        let source = "Local project and tasks · \(project.monitoringSource)"
        let card = JarvisResponseCard(
            title: project.name,
            status: project.status,
            facts: facts,
            source: source,
            projectID: project.id
        )
        return result("Here is the latest available information for \(project.name).", card: card)
    }

    private static func words(in text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func meaningfulWords(in text: String) -> [String] {
        let ignored: Set<String> = ["the", "and", "for", "my", "site", "website", "project", "services", "digital", "company", "co", "app"]
        return words(in: text).filter { $0.count >= 3 && !ignored.contains($0) }
    }

    private static func contains(_ input: String, _ phrases: [String]) -> Bool { phrases.contains { input.contains($0) } }
    private static func plural(_ noun: String, _ count: Int) -> String { count == 1 ? noun : "\(noun)s" }

    private static func namedSummary(_ names: [String], empty: String, prefix: String) -> String {
        guard !names.isEmpty else { return empty }
        let displayed = names.prefix(3).map { "“\($0)”" }.joined(separator: ", ")
        let remainder = names.count > 3 ? " and \(names.count - 3) more" : ""
        return "\(prefix): \(displayed)\(remainder)."
    }
}
