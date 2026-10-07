import Foundation
import SwiftData
import Testing
@testable import JarvisDashboard

struct ProjectItemTests {
    @Test func mapsLegacyStatusesToPhaseOneStatuses() {
        let project = ProjectItem(name: "Legacy")

        project.statusRawValue = "planning"
        #expect(project.status == .notStarted)

        project.statusRawValue = "waiting"
        #expect(project.status == .onHold)
    }

    @Test func archiveStateTracksStatus() {
        let project = ProjectItem(name: "Launch")

        project.status = .archived
        #expect(project.isArchived)
        #expect(project.archivedAt != nil)

        project.status = .active
        #expect(!project.isArchived)
        #expect(project.archivedAt == nil)
    }

    @Test func duplicateCopiesProjectFieldsButStartsFresh() {
        let project = ProjectItem(
            name: "Client Website",
            client: "Example Co",
            type: "Website Build",
            status: .archived,
            priority: .urgent,
            tags: ["WordPress", "SEO"]
        )

        let copy = project.duplicate()

        #expect(copy.name == "Client Website Copy")
        #expect(copy.client == "Example Co")
        #expect(copy.type == "Website Build")
        #expect(copy.priority == .urgent)
        #expect(copy.tags == ["WordPress", "SEO"])
        #expect(copy.status == .notStarted)
        #expect(copy.id != project.id)
    }

    @Test func persistsPhaseOneFieldsInSwiftData() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ProjectItem.self, configurations: configuration)
        let context = ModelContext(container)
        let dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        let project = ProjectItem(
            name: "JAK Pest Control Services",
            client: "JAK",
            type: "Website Build",
            summary: "Rebuild the client website.",
            status: .inReview,
            priority: .high,
            dueDate: dueDate,
            tags: ["WordPress", "SEO"]
        )

        context.insert(project)
        try context.save()

        let verificationContext = ModelContext(container)
        let stored = try #require(verificationContext.fetch(FetchDescriptor<ProjectItem>()).first)
        #expect(stored.name == "JAK Pest Control Services")
        #expect(stored.client == "JAK")
        #expect(stored.type == "Website Build")
        #expect(stored.status == .inReview)
        #expect(stored.priority == .high)
        #expect(stored.dueDate == dueDate)
        #expect(stored.tags == ["WordPress", "SEO"])
    }
}
