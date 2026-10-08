import Foundation
import SwiftData

@Model
final class ProjectItem {
    var id: UUID = UUID()
    var name: String
    var client: String
    var type: String = ""
    var summary: String
    var statusRawValue: String
    var priorityRawValue: String = ProjectPriority.medium.rawValue
    var modeRawValue: String = ProjectMode.fixed.rawValue
    var progress: Double
    var nextAction: String
    var startDate: Date?
    var dueDate: Date?
    var tagsRawValue: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date
    var archivedAt: Date?
    var statusChangedAt: Date = Date.now
    var repositoryPath: String = ""
    var repositoryBookmarkData: Data?
    var monitoringWebsiteURL: String = ""
    var monitoringPlatformRawValue: String = MonitoringPlatform.generic.rawValue
    var monitoringSiteID: String = ""
    var monitoringConnectedAt: Date?

    init(
        name: String,
        client: String = "",
        type: String = "",
        summary: String = "",
        status: ProjectStatus = .active,
        priority: ProjectPriority = .medium,
        mode: ProjectMode = .fixed,
        progress: Double = 0,
        nextAction: String = "",
        startDate: Date? = nil,
        dueDate: Date? = nil,
        tags: [String] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.name = name
        self.client = client
        self.type = type
        self.summary = summary
        self.statusRawValue = status.rawValue
        self.priorityRawValue = priority.rawValue
        self.modeRawValue = mode.rawValue
        self.progress = progress
        self.nextAction = nextAction
        self.startDate = startDate
        self.dueDate = dueDate
        self.tagsRawValue = Self.encodeTags(tags)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
    }

    var status: ProjectStatus {
        get {
            switch statusRawValue {
            case "planning": .notStarted
            case "waiting": .onHold
            default: ProjectStatus(rawValue: statusRawValue) ?? .active
            }
        }
        set {
            if statusRawValue != newValue.rawValue {
                statusChangedAt = .now
            }
            statusRawValue = newValue.rawValue
            archivedAt = newValue == .archived ? (archivedAt ?? .now) : nil
        }
    }

    var priority: ProjectPriority {
        get { ProjectPriority(rawValue: priorityRawValue) ?? .medium }
        set { priorityRawValue = newValue.rawValue }
    }

    var mode: ProjectMode {
        get { ProjectMode(rawValue: modeRawValue) ?? .fixed }
        set { modeRawValue = newValue.rawValue }
    }

    var hasRepository: Bool {
        repositoryBookmarkData != nil && !repositoryPath.isEmpty
    }

    var hasMonitoringSite: Bool {
        !monitoringSiteID.isEmpty && !monitoringWebsiteURL.isEmpty
    }

    var monitoringPlatform: MonitoringPlatform {
        get { MonitoringPlatform(rawValue: monitoringPlatformRawValue) ?? .generic }
        set { monitoringPlatformRawValue = newValue.rawValue }
    }

    var tags: [String] {
        get {
            tagsRawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set { tagsRawValue = Self.encodeTags(newValue) }
    }

    var isArchived: Bool { status == .archived || archivedAt != nil }

    func waitingDays(now: Date = .now, calendar: Calendar = .current) -> Int? {
        guard status == .waitingOnClient else { return nil }
        return max(0, calendar.dateComponents([.day], from: statusChangedAt, to: now).day ?? 0)
    }

    func duplicate() -> ProjectItem {
        ProjectItem(
            name: "\(name) Copy",
            client: client,
            type: type,
            summary: summary,
            status: status == .archived ? .notStarted : status,
            priority: priority,
            mode: mode,
            progress: progress,
            nextAction: nextAction,
            startDate: startDate,
            dueDate: dueDate,
            tags: tags
        )
    }

    private static func encodeTags(_ tags: [String]) -> String {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

enum MonitoringPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case generic
    case wordpress
    case laravel
    case node
    case `static`
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .generic: "Generic"
        case .wordpress: "WordPress"
        case .laravel: "Laravel"
        case .node: "Node"
        case .static: "Static"
        case .custom: "Custom"
        }
    }
}

enum ProjectStatus: String, CaseIterable, Identifiable {
    case notStarted = "not_started"
    case active
    case inReview = "in_review"
    case onHold = "on_hold"
    case waitingOnClient = "waiting_on_client"
    case completed
    case archived

    var id: Self { self }

    var title: String {
        switch self {
        case .notStarted: "Not Started"
        case .active: "Active"
        case .inReview: "In Review"
        case .onHold: "On Hold"
        case .waitingOnClient: "Waiting on Client"
        case .completed: "Completed"
        case .archived: "Archived"
        }
    }
}

enum ProjectPriority: String, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case urgent

    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum ProjectMode: String, CaseIterable, Identifiable {
    case fixed
    case ongoing

    var id: Self { self }

    var title: String {
        switch self {
        case .fixed: "Fixed Project"
        case .ongoing: "Ongoing Client"
        }
    }

    var explanation: String {
        switch self {
        case .fixed: "Progress is measured toward a defined finish."
        case .ongoing: "Health and recent activity replace lifetime completion."
        }
    }
}
