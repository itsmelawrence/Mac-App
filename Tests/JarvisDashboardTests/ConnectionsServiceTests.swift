import Foundation
import Testing
@testable import JarvisDashboard

struct ConnectionsServiceTests {
    @Test func registeredProjectsExposeSourceTreeAndConnections() throws {
        let vault = try fixture()
        defer { try? FileManager.default.removeItem(at: vault) }
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
        defer { try? FileManager.default.removeItem(at: vault) }
        let project = try #require(ConnectionsService.projects(in: vault).first)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString)")
        try "private".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: project.rootURL.appendingPathComponent("outside"), withDestinationURL: outside)
        let children = ConnectionsService.children(of: project.rootURL, in: project)
        #expect(!children.contains(where: { $0.name == ".build" || $0.name == "outside" }))
        #expect(ConnectionsService.children(of: vault, in: project).isEmpty)
    }

    @Test func newVaultProjectsAppearWithoutAddingICMRoutes() throws {
        let vault = try fixture()
        defer { try? FileManager.default.removeItem(at: vault) }
        let manager = FileManager.default
        let files: [String: String] = [
            "Work/Pixeld/New Site/index.html": "<!doctype html>",
            "Personal/Skeema/New API/composer.json": "{}",
            "Personal/Skeema/New API/public/index.php": "<?php",
            "Personal/Empty Folder/readme.txt": "not a project marker",
            "Personal/Skeema/New API/node_modules/example/package.json": "{}"
        ]
        for (path, contents) in files {
            let url = vault.appendingPathComponent(path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        let registeredGit = vault.appendingPathComponent("Personal/Mac App/.git")
        try manager.createDirectory(at: registeredGit, withIntermediateDirectories: true)

        let projects = try ConnectionsService.projects(in: vault)
        #expect(projects.count == 3)
        #expect(projects.filter(\.isRegistered).map(\.name) == ["JARVIS"])
        #expect(Set(projects.filter { !$0.isRegistered }.map(\.route.projectPath)) == [
            "Work/Pixeld/New Site", "Personal/Skeema/New API"
        ])
        #expect(!projects.contains { $0.route.projectPath.hasSuffix("/public") })
        #expect(!projects.contains { $0.route.projectPath.contains("node_modules") })
    }

    @Test func brokenRoutesAreReportedWithoutHidingOtherProjects() throws {
        let vault = try fixture()
        defer { try? FileManager.default.removeItem(at: vault) }
        let site = vault.appendingPathComponent("Personal/Apps/Site/index.html")
        try FileManager.default.createDirectory(at: site.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "<!doctype html>".write(to: site, atomically: true, encoding: .utf8)
        let manifest = ICMManifest(version: 1, routes: [
            ICMRoute(id: "jarvis", name: "JARVIS", aliases: [], projectPath: "Personal/Mac App",
                     contextPath: "Notes/Projects/Personal/Mac App/PROJECT.md",
                     graphPath: "Graphify/JARVIS", entrypoints: [], graphNotes: []),
            ICMRoute(id: "moved", name: "Moved", aliases: [], projectPath: "Personal/ChatGPT/Moved",
                     contextPath: "Notes/Projects/Personal/ChatGPT/Moved/PROJECT.md",
                     graphPath: "Graphify/Moved", entrypoints: [], graphNotes: []),
            ICMRoute(id: "unsafe", name: "Unsafe", aliases: [], projectPath: "Personal/Apps",
                     contextPath: "../outside.md", graphPath: "Graphify/Apps", entrypoints: [], graphNotes: [])
        ])
        try JSONEncoder().encode(manifest).write(to: vault.appendingPathComponent("ICM/routes.json"))

        let workspace = try ConnectionsService.workspace(in: vault)
        #expect(workspace.routeIssues == [
            "Moved: The routed project folder is missing: Personal/ChatGPT/Moved.",
            "Unsafe: The ICM routes file contains an unsafe path: ../outside.md."
        ])
        #expect(workspace.projects.filter(\.isRegistered).map(\.name) == ["JARVIS"])
        #expect(workspace.projects.contains { !$0.isRegistered && $0.route.projectPath == "Personal/Apps/Site" })
    }

    private func fixture() throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-connections-\(UUID().uuidString)")
        let files: [String: String] = [
            "CONTEXT.md": "# Router",
            "Personal/Mac App/Sources/TodayView.swift": "// source",
            "Personal/Mac App/.build/generated.txt": "ignored",
            "Notes/Projects/Personal/Mac App/PROJECT.md": "# Project",
            "Graphify/JARVIS/TodayView.swift.md": "---\nsource_file: \"Sources/TodayView.swift\"\n---\n## Connections\n- [[Graphify/JARVIS/CommandPanel|CommandPanel]] - `contains` [EXTRACTED]",
            "Graphify/JARVIS/CommandPanel.md": "# CommandPanel"
        ]
        for (path, contents) in files {
            let file = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        let manifest = ICMManifest(version: 1, routes: [
            ICMRoute(id: "jarvis", name: "JARVIS", aliases: ["Mac App"],
                     projectPath: "Personal/Mac App",
                     contextPath: "Notes/Projects/Personal/Mac App/PROJECT.md",
                     graphPath: "Graphify/JARVIS", entrypoints: [], graphNotes: [])
        ])
        let url = vault.appendingPathComponent("ICM/routes.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: url)
        return vault
    }
}
