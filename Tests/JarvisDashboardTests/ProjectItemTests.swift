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

    @Test func waitingOnClientTracksStatusAge() {
        let project = ProjectItem(name: "Content handoff")
        project.status = .waitingOnClient
        project.statusChangedAt = Date(timeIntervalSince1970: 1_000_000)
        let threeDaysLater = project.statusChangedAt.addingTimeInterval(3 * 86_400)

        #expect(project.waitingDays(now: threeDaysLater) == 3)
    }

    @Test func taskCanBelongToProjectAndBeBlocked() {
        let projectID = UUID()
        let task = TaskItem(
            title: "Await homepage copy",
            projectID: projectID,
            isBlocked: true,
            blockedReason: "Waiting for client content"
        )

        #expect(task.projectID == projectID)
        #expect(task.isBlocked)
        #expect(task.blockedReason == "Waiting for client content")
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
        #expect(!copy.hasMonitoringSite)
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
            mode: .ongoing,
            dueDate: dueDate,
            tags: ["WordPress", "SEO"]
        )

        context.insert(project)
        project.monitoringWebsiteURL = "https://example.com"
        project.monitoringPlatform = .custom
        project.monitoringSiteID = "site-123"
        project.monitoringConnectedAt = dueDate
        try context.save()

        let verificationContext = ModelContext(container)
        let stored = try #require(verificationContext.fetch(FetchDescriptor<ProjectItem>()).first)
        #expect(stored.name == "JAK Pest Control Services")
        #expect(stored.client == "JAK")
        #expect(stored.type == "Website Build")
        #expect(stored.status == .inReview)
        #expect(stored.priority == .high)
        #expect(stored.mode == .ongoing)
        #expect(stored.dueDate == dueDate)
        #expect(stored.tags == ["WordPress", "SEO"])
        #expect(stored.monitoringWebsiteURL == "https://example.com")
        #expect(stored.monitoringPlatform == .custom)
        #expect(stored.monitoringSiteID == "site-123")
        #expect(stored.monitoringConnectedAt == dueDate)
    }
}
