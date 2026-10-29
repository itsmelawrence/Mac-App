import Foundation
import SwiftData

/// Project changes that touch more than the project model itself.
@MainActor
enum ProjectStore {
    /// Deletes a project. Its tasks move to the inbox rather than keeping a dangling
    /// `projectID`, which would make every later backup fail to import.
    static func delete(_ project: ProjectItem, from context: ModelContext) throws {
        let projectID = project.id
        let tasks = try context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.projectID == projectID }))
        for task in tasks { task.projectID = nil }
        context.delete(project)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
