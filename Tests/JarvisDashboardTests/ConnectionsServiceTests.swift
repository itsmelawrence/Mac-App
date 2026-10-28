import Foundation
import Testing
@testable import JarvisDashboard

struct ConnectionsServiceTests {
    @Test func registeredProjectsExposeSourceTreeAndConnections() throws {
        let vault = try fixture()
        defer { try? FileManager.default.removeItem(at: vault.deletingLastPathComponent()) }
        let project = try #require(ConnectionsService.projects(in: vault).first)
        #expect(project.name == "JARVIS")

        let children = ConnectionsService.children(of: project.rootURL, in: project)
        #expect(children.map(\.name) == ["Sources"])
        let sources = try #require(children.first)
        let file = try #require(ConnectionsService.children(of: sources.url, in: project).first)
        #expect(file.relativePath == "Sources/TodayView.swift")
        #expect(ConnectionsService.search("TodayView", in: project).map(\.relativePath) == ["Sources/TodayView.swift"])

        let notes = ConnectionsService.notes(for: file, in: project, vaultURL: vault)
        #expect(notes.map(\.title) == ["Project context", "Graphify: TodayView.swift", "CommandPanel"])
        #expect(notes.last?.relation == "contains")
    }

    @Test func sourceTreeDoesNotFollowSymlinksOrShowGeneratedFolders() throws {
        let vault = try fixture()
        defer { try? FileManager.default.removeItem(at: vault.deletingLastPathComponent()) }
        let project = try #require(ConnectionsService.projects(in: vault).first)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: project.rootURL.appendingPathComponent("outside"), withDestinationURL: outside)
        let children = ConnectionsService.children(of: project.rootURL, in: project)
        #expect(!children.contains(where: { $0.name == ".build" || $0.name == "outside" }))
        #expect(ConnectionsService.children(of: vault, in: project).isEmpty)
    }

    @Test func vaultHealthReadsDoctorReportAndToleratesItsAbsence() throws {
        let vault = try fixture()
        defer { try? FileManager.default.removeItem(at: vault.deletingLastPathComponent()) }
        #expect(ConnectionsService.health(in: vault) == nil)

        let report = """
        {"version": 1, "checkedAt": "2026-10-28T18:26:13+08:00", "errors": 1, "warnings": 2,
         "stats": {"projects": 47},
         "issues": [{"level": "error", "check": "routes", "message": "JARVIS: project folder missing", "path": "Personal/Old"}]}
        """
        let url = vault.appendingPathComponent("ICM/health.json")
        try report.write(to: url, atomically: true, encoding: .utf8)
        let health = try #require(ConnectionsService.health(in: vault))
        #expect(health.errors == 1 && health.warnings == 2)
        #expect(health.issues.first?.path == "Personal/Old")
        #expect(health.checkedAt == ISO8601DateFormatter().date(from: "2026-10-28T10:26:13Z"))

        try "{not json".write(to: url, atomically: true, encoding: .utf8)
        #expect(ConnectionsService.health(in: vault) == nil)
    }

    @Test func workspaceComesFromICMAndSkipsUnsafePathsInItsReply() throws {
        let stub = try StubVault(reply: """
        {"status": "ok", "routeIssues": ["Moved: The routed project folder is missing: Personal/Moved."], "projects": [
          {"id": "jarvis", "name": "JARVIS", "aliases": [], "projectPath": "Personal/Mac App",
           "contextPath": "Notes/Projects/Personal/Mac App/PROJECT.md", "graphPath": "Graphify/JARVIS",
           "entrypoints": [], "graphNotes": [], "registered": true},
          {"id": "discovered:Work/Site", "name": "Site", "aliases": [], "projectPath": "Work/Site",
           "contextPath": "Notes/Projects/Work/Site/PROJECT.md", "graphPath": "Graphify/_discovered/Work__Site",
           "entrypoints": [], "graphNotes": [], "registered": false},
          {"id": "bad", "name": "Bad", "aliases": [], "projectPath": "../outside", "contextPath": "x.md",
           "graphPath": "Graphify/Bad", "entrypoints": [], "graphNotes": [], "registered": true}]}
        """)
        defer { stub.remove() }
        let workspace = try ConnectionsService.workspace(in: stub.vault)
        #expect(workspace.projects.map(\.name) == ["JARVIS", "Site"])
        #expect(workspace.projects.map(\.isRegistered) == [true, false])
        #expect(workspace.routeIssues == ["Moved: The routed project folder is missing: Personal/Moved."])

        let broken = try StubVault(reply: #"{"status": "error", "message": "This ICM routes file uses an unsupported version."}"#)
        defer { broken.remove() }
        #expect {
            try ConnectionsService.workspace(in: broken.vault)
        } throws: { $0.localizedDescription == "This ICM routes file uses an unsupported version." }
    }

    private func fixture() throws -> URL {
        let stub = try StubVault(reply: """
        {"status": "ok", "routeIssues": [], "projects": [
          {"id": "jarvis", "name": "JARVIS", "aliases": ["Mac App"], "projectPath": "Personal/Mac App",
           "contextPath": "Notes/Projects/Personal/Mac App/PROJECT.md", "graphPath": "Graphify/JARVIS",
           "entrypoints": [], "graphNotes": [], "registered": true}]}
        """, files: [
            "Projects/Personal/Mac App/Sources/TodayView.swift": "// source",
            "Projects/Personal/Mac App/.build/generated.txt": "ignored",
            "Projects/Notes/Projects/Personal/Mac App/PROJECT.md": "# Project",
            "Projects/Graphify/JARVIS/TodayView.swift.md": "---\nsource_file: \"Sources/TodayView.swift\"\n---\n## Connections\n- [[Graphify/JARVIS/CommandPanel|CommandPanel]] - `contains` [EXTRACTED]",
            "Projects/Graphify/JARVIS/CommandPanel.md": "# CommandPanel",
            "Projects/ICM/routes.json": #"{"version": 1, "routes": []}"#
        ])
        return stub.vault
    }
}
