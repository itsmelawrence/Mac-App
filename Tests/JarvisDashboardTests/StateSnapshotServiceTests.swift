import Foundation
import Testing
@testable import JarvisDashboard

@MainActor
struct StateSnapshotServiceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeService() -> (StateSnapshotService, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        return (StateSnapshotService(fileURL: url, appVersion: "9.9.9", writeDelay: .seconds(60)), url)
    }

    @Test func storeSectionFollowsTheQueueAndNamesProjects() {
        let (service, _) = makeService()
        let project = ProjectItem(name: "Clinic site", client: "Acme")
        let overdue = TaskItem(title: "Overdue", dueDate: now.addingTimeInterval(-60), projectID: project.id)
        let blocked = TaskItem(title: "Blocked", priority: .critical, isBlocked: true, blockedReason: "Waiting on DNS")
        let done = TaskItem(title: "Done", isCompleted: true)

        service.recordStore(tasks: [done, blocked, overdue], projects: [project], now: now)
        let snapshot = service.snapshot(now: now)

        #expect(snapshot.store?.tasks.map(\.title) == ["Overdue", "Blocked", "Done"])
        #expect(snapshot.store?.tasks[0].isOverdue == true)
        #expect(snapshot.store?.tasks[0].project == "Clinic site")
        #expect(snapshot.store?.tasks[1].blockedReason == "Waiting on DNS")
        #expect(snapshot.store?.projects.first?.openTasks == 1)
        #expect(snapshot.briefing?.text.contains("1 overdue task") == true)
        // Nothing fetched sites or news yet, so those sections are absent, not empty.
        #expect(snapshot.sites == nil)
        #expect(snapshot.intelligence == nil)
    }

    @Test func sitesAreLinkedToTheirProject() {
        let (service, _) = makeService()
        let project = ProjectItem(name: "Clinic site")
        project.monitoringWebsiteURL = "https://example.com"
        service.recordStore(tasks: [], projects: [project], now: now)
        var record = SiteRecord(url: "https://example.com/")
        record.record(SiteCheck(checkedAt: now.addingTimeInterval(-60), outcome: .failed, error: "HTTP 503"))
        record.record(SiteCheck(checkedAt: now, outcome: .failed, statusCode: 503, error: "HTTP 503"))

        service.recordSites([project.id: record], now: now)
        let snapshot = service.snapshot(now: now)
        let entry = snapshot.sites?.items.first

        #expect(snapshot.store?.projects.first?.monitoringSiteId == project.id.uuidString)
        #expect(entry?.siteId == project.id.uuidString)
        #expect(entry?.project == "Clinic site")
        #expect(entry?.state == "Down")
        #expect(entry?.needsAttention == true)
        #expect(entry?.downSince == now.addingTimeInterval(-60))
        #expect(entry?.uptimePercent == 0)
    }

    @Test func writesPrivateSnakeCaseJSONForTheTools() throws {
        let (service, url) = makeService()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        service.recordStore(tasks: [TaskItem(title: "Ship it", isBlocked: true)], projects: [], now: now)

        try service.writeNow(now: now)

        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["schema"] as? Int == StateSnapshotService.schemaVersion)
        #expect(object["app_version"] as? String == "9.9.9")
        #expect(object["as_of"] as? String == "2027-01-15T08:00:00Z")
        let store = try #require(object["store"] as? [String: Any])
        let task = try #require((store["tasks"] as? [[String: Any]])?.first)
        #expect(task["is_blocked"] as? Bool == true)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }
}
