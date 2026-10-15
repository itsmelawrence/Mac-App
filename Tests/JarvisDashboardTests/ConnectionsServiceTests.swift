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

    private func fixture() throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-connections-\(UUID().uuidString)")
        let files: [String: String] = [
            "CONTEXT.md": "# Router",
            "Personal/ChatGPT/Mac App/Sources/TodayView.swift": "// source",
            "Personal/ChatGPT/Mac App/.build/generated.txt": "ignored",
            "Notes/Projects/Personal/ChatGPT/Mac App/PROJECT.md": "# Project",
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
                     projectPath: "Personal/ChatGPT/Mac App",
                     contextPath: "Notes/Projects/Personal/ChatGPT/Mac App/PROJECT.md",
                     graphPath: "Graphify/JARVIS", entrypoints: [], graphNotes: [])
        ])
        let url = vault.appendingPathComponent("ICM/routes.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: url)
        return vault
    }
}
