import Foundation
import SwiftData

@Model
final class ProjectItem {
    var name: String
    var client: String
    var summary: String
    var statusRawValue: String
    var progress: Double
    var nextAction: String
    var updatedAt: Date

    init(
        name: String,
        client: String = "",
        summary: String = "",
        status: ProjectStatus = .active,
        progress: Double = 0,
        nextAction: String = "",
        updatedAt: Date = .now
    ) {
        self.name = name
        self.client = client
        self.summary = summary
        self.statusRawValue = status.rawValue
        self.progress = progress
        self.nextAction = nextAction
        self.updatedAt = updatedAt
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }
}

enum ProjectStatus: String, CaseIterable, Identifiable {
    case planning
    case active
    case waiting
    case completed
    case archived

    var id: Self { self }
    var title: String { rawValue.capitalized }
}
