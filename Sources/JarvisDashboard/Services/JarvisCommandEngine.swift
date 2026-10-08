import Foundation

struct JarvisCommandContext: Equatable, Sendable {
    let briefing: String
    let pendingTasks: Int
    let overdueTasks: Int
    let activeProjects: Int
    let monitoredSites: Int
    let unhealthySites: Int
}

struct JarvisCommandResult: Equatable, Sendable {
    let response: String
    let destination: SidebarDestination?
    let shouldSpeak: Bool
}

enum JarvisCommandEngine {
    static func execute(_ command: String, context: JarvisCommandContext) -> JarvisCommandResult {
        let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalized.isEmpty else {
            return JarvisCommandResult(response: "Awaiting your command, Sir.", destination: nil, shouldSpeak: false)
        }

        if containsAny(normalized, ["briefing", "brief me", "status report", "situation report"]) {
            return JarvisCommandResult(response: context.briefing, destination: .today, shouldSpeak: true)
        }

        if containsAny(normalized, ["task", "to-do", "todo", "overdue"]) {
            let response = context.overdueTasks > 0
                ? "You have \(context.pendingTasks) open tasks, including \(context.overdueTasks) overdue. Opening the task queue."
                : "You have \(context.pendingTasks) open tasks and none are overdue. Opening the task queue."
            return JarvisCommandResult(response: response, destination: .tasks, shouldSpeak: false)
        }

        if containsAny(normalized, ["project", "client", "site", "monitoring", "website"]) {
            let siteStatus: String
            if context.monitoredSites == 0 {
                siteStatus = "No monitored websites are connected."
            } else if context.unhealthySites == 0 {
                siteStatus = "All \(context.monitoredSites) monitored websites are healthy."
            } else {
                siteStatus = "\(context.unhealthySites) of \(context.monitoredSites) monitored websites require attention."
            }
            return JarvisCommandResult(
                response: "\(context.activeProjects) projects are currently active. \(siteStatus) Opening operations.",
                destination: .projects,
                shouldSpeak: false
            )
        }

        if containsAny(normalized, ["weather", "news", "earthquake", "intelligence", "alert"]) {
            return JarvisCommandResult(response: "Opening live intelligence and regional signals.", destination: .intelligence, shouldSpeak: false)
        }

        if containsAny(normalized, ["setting", "voice", "speech", "configure", "configuration"]) {
            return JarvisCommandResult(response: "Opening system configuration.", destination: .settings, shouldSpeak: false)
        }

        if containsAny(normalized, ["today", "command centre", "command center", "home"]) {
            return JarvisCommandResult(response: "Returning to the command centre.", destination: .today, shouldSpeak: false)
        }

        return JarvisCommandResult(
            response: "I can brief you or open tasks, projects, monitoring, intelligence, weather, news, and settings. Broader conversational control is the next system upgrade.",
            destination: nil,
            shouldSpeak: false
        )
    }

    private static func containsAny(_ command: String, _ terms: [String]) -> Bool {
        terms.contains(where: command.contains)
    }
}
