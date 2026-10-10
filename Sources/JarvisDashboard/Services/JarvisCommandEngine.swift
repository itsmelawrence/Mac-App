import Foundation

struct JarvisCommandContext: Equatable, Sendable {
    let briefing: String
    let pendingTasks: Int
    let overdueTasks: Int
    let activeProjects: Int
    let monitoredSites: Int
    let unhealthySites: Int
    let unverifiedSites: Int
    let maintenanceSites: Int
    let monitoringAvailable: Bool
    let priorityTask: String?
    let blockedTaskNames: [String]
    let waitingProjectNames: [String]
    let unhealthySiteNames: [String]
    let weatherReport: String?
}

struct JarvisCommandResult: Equatable, Sendable {
    let response: String
    let destination: SidebarDestination?
    let shouldSpeak: Bool
}

enum JarvisCommandEngine {
    static func execute(_ command: String, context: JarvisCommandContext) -> JarvisCommandResult {
        let input = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !input.isEmpty else { return result("Awaiting your command, Sir.") }

        if contains(input, ["help", "what can you do", "commands"]) {
            return result("Try: Brief me; What needs attention?; What should I work on?; Show blocked tasks; Which clients are waiting?; Are my sites healthy?; What's the weather? You can also open Tasks, Projects, Intelligence, or Settings.")
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
            if context.maintenanceSites > 0 { items.append("\(context.maintenanceSites) \(plural("site", context.maintenanceSites)) in maintenance") }
            if context.monitoredSites > 0 && !context.monitoringAvailable { items.append("monitoring data is unavailable") }
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
            guard context.monitoredSites > 0 else { return result("No monitored websites are connected.") }
            guard context.monitoringAvailable else { return result("Monitoring data is unavailable. I cannot confirm whether your websites are healthy. Check the API connection in Settings.") }
            var parts: [String] = []
            if !context.unhealthySiteNames.isEmpty { parts.append(namedSummary(context.unhealthySiteNames, empty: "", prefix: "Needs attention")) }
            if context.unverifiedSites > 0 { parts.append("\(context.unverifiedSites) \(plural("site", context.unverifiedSites)) awaiting checks.") }
            if context.maintenanceSites > 0 { parts.append("\(context.maintenanceSites) \(plural("site", context.maintenanceSites)) in maintenance.") }
            return result(parts.isEmpty ? "All \(context.monitoredSites) monitored websites are healthy." : parts.joined(separator: " "))
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
        return result("I can brief you, identify work needing attention, suggest your next task, report site health and weather, or open a dashboard section. Say “help” for examples. Broader conversational control awaits the local model.")
    }

    private static func result(_ response: String, destination: SidebarDestination? = nil, speak: Bool = false) -> JarvisCommandResult {
        JarvisCommandResult(response: response, destination: destination, shouldSpeak: speak)
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
