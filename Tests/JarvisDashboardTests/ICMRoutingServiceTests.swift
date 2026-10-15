import Foundation
import Testing
@testable import JarvisDashboard

struct ICMRoutingServiceTests {
    @Test func workRequestRoutesToOneProjectAndProducesSmallHandoff() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let result = try ICMRoutingService.prepare(prompt: "Update the JARVIS UI", vaultURL: vault)
        let prepared = try #require(result)
        #expect(prepared.route.id == "jarvis")
        #expect(prepared.handoff.contains("Project root: "))
        #expect(prepared.handoff.contains("ProjectsView.swift"))
        #expect(prepared.graphURLs.count == 1)
        #expect(!prepared.handoff.contains("portfolio"))
    }

    @Test func ambiguousPromptDoesNotChooseAProject() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        #expect(throws: ICMRoutingError.self) {
            _ = try ICMRoutingService.prepare(prompt: "Update JARVIS and portfolio", vaultURL: vault)
        }
    }

    @Test func promptCaptureStaysInsideProjectIntake() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let result = try ICMRoutingService.prepare(prompt: "Fix JARVIS", vaultURL: vault)
        let route = try #require(result).route
        let file = try ICMRoutingService.capture(prompt: "Fix JARVIS", route: route, vaultURL: vault)
        #expect(file.path.contains("Memory/01_intake/Personal/ChatGPT/Mac App/"))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("Fix JARVIS"))
    }

    private func makeVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-icm-\(UUID().uuidString)")
        let files: [String: String] = [
            "CONTEXT.md": "# Router",
            "Personal/ChatGPT/Mac App/Sources/ProjectsView.swift": "// source",
            "Personal/Skeema/LawrencePortfolio1/routes/web.php": "<?php",
            "Memory/03_references/JARVIS.md": "# JARVIS",
            "Memory/03_references/LawrencePortfolio.md": "# Portfolio",
            "Graphify/JARVIS/ProjectsView.swift.md": "# ProjectsView",
        ]
        for (path, contents) in files {
            let file = vault.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        let routes = ICMManifest(version: 1, routes: [
            ICMRoute(id: "jarvis", name: "JARVIS", aliases: ["Mac App"],
                     projectPath: "Personal/ChatGPT/Mac App", contextPath: "Memory/03_references/JARVIS.md",
                     graphPath: "Graphify/JARVIS", entrypoints: ["Sources/ProjectsView.swift"],
                     graphNotes: ["ProjectsView.swift.md"]),
            ICMRoute(id: "portfolio", name: "LawrencePortfolio", aliases: ["portfolio"],
                     projectPath: "Personal/Skeema/LawrencePortfolio1",
                     contextPath: "Memory/03_references/LawrencePortfolio.md",
                     graphPath: "Graphify/LawrencePortfolio", entrypoints: ["routes/web.php"],
                     graphNotes: [])
        ])
        let manifest = vault.appendingPathComponent("ICM/routes.json")
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(routes).write(to: manifest)
        return vault
    }
}
