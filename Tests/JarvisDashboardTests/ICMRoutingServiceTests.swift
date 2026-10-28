import Foundation
import Testing
@testable import JarvisDashboard

/// A temporary `<root>/Projects` vault whose `<root>/.tools/icm.py` is a stand-in replying with `reply`.
/// The routing rules themselves are tested in the vault tools (`.tools/tests/test_icm.py`).
struct StubVault {
    let root: URL
    var vault: URL { root.appendingPathComponent("Projects") }

    init(reply: String?, files: [String: String] = [:]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-icm-\(UUID().uuidString)")
        var all = files
        all["Projects/CONTEXT.md"] = "# Router"
        if let reply {
            all[".tools/reply.json"] = reply
            // Echoes the prompt (read from standard input) into the handoff, and prints noise first,
            // as a real script's warnings would.
            all[".tools/icm.py"] = """
            import json, sys
            from pathlib import Path
            prompt = sys.stdin.read()
            reply = json.loads((Path(__file__).parent / "reply.json").read_text())
            if "handoff" in reply:
                reply["handoff"] = "Task: " + prompt
            print("a warning line")
            print(json.dumps(reply))
            """
        }
        for (path, contents) in all {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

struct ICMRoutingServiceTests {
    private let jarvisRoute = """
    {"id": "jarvis", "name": "JARVIS", "aliases": ["Mac App"], "projectPath": "Personal/Mac App",
     "contextPath": "Notes/Projects/Personal/Mac App/PROJECT.md", "graphPath": "Graphify/JARVIS",
     "entrypoints": [], "graphNotes": []}
    """

    @Test func routedReplyBecomesAPreparedRouteAndThePromptGoesOnStandardInput() throws {
        let stub = try StubVault(reply: """
        {"status": "routed", "route": \(jarvisRoute), "projectRoot": "/vault/Personal/Mac App",
         "context": "/vault/Notes/Projects/Personal/Mac App/PROJECT.md",
         "graphNotes": ["/vault/Graphify/JARVIS/TodayView.swift.md"], "handoff": ""}
        """)
        defer { stub.remove() }
        let prepared = try #require(try ICMRoutingService.prepare(prompt: "Fix JARVIS's \"Today\" view", vaultURL: stub.vault))
        #expect(prepared.route.id == "jarvis")
        #expect(prepared.projectURL.path == "/vault/Personal/Mac App")
        #expect(prepared.graphURLs.map(\.lastPathComponent) == ["TodayView.swift.md"])
        #expect(prepared.handoff == "Task: Fix JARVIS's \"Today\" view")
    }

    @Test func unmatchedIsNilAndAmbiguousNamesTheCandidates() throws {
        let unmatched = try StubVault(reply: #"{"status": "unmatched"}"#)
        defer { unmatched.remove() }
        #expect(try ICMRoutingService.prepare(prompt: "Tidy up", vaultURL: unmatched.vault) == nil)

        let ambiguous = try StubVault(reply: #"{"status": "ambiguous", "candidates": ["JARVIS", "Portfolio"]}"#)
        defer { ambiguous.remove() }
        #expect {
            try ICMRoutingService.prepare(prompt: "Fix JARVIS and Portfolio", vaultURL: ambiguous.vault)
        } throws: { error in
            error.localizedDescription == "More than one project matches: JARVIS, Portfolio. Name the intended project."
        }
    }

    @Test func scriptErrorsAndCrashesSurfaceAsMessages() throws {
        let broken = try StubVault(reply: #"{"status": "error", "message": "The routed project folder is missing: Personal/Old."}"#)
        defer { broken.remove() }
        #expect {
            try ICMRoutingService.prepare(prompt: "Fix JARVIS", vaultURL: broken.vault)
        } throws: { $0.localizedDescription == "The routed project folder is missing: Personal/Old." }

        let crash = try StubVault(reply: "not json")
        defer { crash.remove() }
        #expect {
            try ICMRoutingService.prepare(prompt: "Fix JARVIS", vaultURL: crash.vault)
        } throws: { $0.localizedDescription.hasPrefix("Vault routing failed:") }

        let missing = try StubVault(reply: nil)
        defer { missing.remove() }
        #expect {
            try ICMRoutingService.prepare(prompt: "Fix JARVIS", vaultURL: missing.vault)
        } throws: { $0.localizedDescription.contains(".tools/icm.py is missing") }
    }

    @Test func promptCaptureStaysInsideProjectIntake() throws {
        let stub = try StubVault(reply: nil)
        defer { stub.remove() }
        let file = try ICMRoutingService.capture(prompt: "Fix JARVIS", route: route(), vaultURL: stub.vault)
        #expect(file.path.contains("Memory/01_intake/Personal/Mac App/"))
        #expect(try String(contentsOf: file, encoding: .utf8).contains("Fix JARVIS"))
    }

    @Test func projectActivityUsesPARAAndLinksToRawPrompt() throws {
        let stub = try StubVault(reply: nil, files: ["Projects/Notes/Projects/Personal/Mac App/PROJECT.md": "# JARVIS"])
        defer { stub.remove() }
        let raw = try ICMRoutingService.capture(prompt: "Fix JARVIS", route: route(), vaultURL: stub.vault)
        let activity = try ICMRoutingService.recordActivity(
            prompt: "Fix JARVIS", route: route(), rawPromptURL: raw, vaultURL: stub.vault
        )
        let contents = try String(contentsOf: activity, encoding: .utf8)
        #expect(activity.path.contains("Notes/Projects/Personal/Mac App/Activities/"))
        #expect(contents.contains("status: requested"))
        #expect(contents.contains("Raw prompt: [[Memory/01_intake/"))
        #expect(contents.contains("Pending agent work."))
    }

    private func route() throws -> ICMRoute {
        try JSONDecoder().decode(ICMRoute.self, from: Data(jarvisRoute.utf8))
    }
}
