import Foundation
import Testing
@testable import JarvisDashboard

struct ConsoleBrainServiceTests {
    private let vault = URL(fileURLWithPath: "/Users/test/Documents/Main/Projects", isDirectory: true)

    @Test func scriptAndPythonLiveInToolsFolderBesideTheVault() {
        #expect(ConsoleBrainService.scriptURL(vaultURL: vault).path == "/Users/test/Documents/Main/.tools/console_brain.py")
        #expect(ConsoleBrainService.pythonURL(vaultURL: vault).path == "/Users/test/Documents/Main/.tools/jarvis_mcp/.venv/bin/python")
    }

    @Test func decodesTheScriptsReply() throws {
        let line = """
        {"answer": "Added it.", "model": "ornith-1.5:9b", "seconds": 24.7, "error": null,
         "calls": [{"tool": "app_list_tasks", "status": null}, {"tool": "app_add_task", "status": "queued"}]}
        """
        let reply = try JSONDecoder().decode(ConsoleBrainReply.self, from: Data(line.utf8))
        #expect(reply.answer == "Added it.")
        #expect(reply.toolsLine == "app_list_tasks, app_add_task (queued)")
        #expect(reply.sourceLine == "Local model · ornith-1.5:9b · 25 s")
        #expect(!reply.awaitsApproval)
    }

    @Test func notesAChangeWaitingForApproval() {
        let reply = ConsoleBrainReply(answer: "", model: "m", seconds: 1,
                                      calls: [.init(tool: "app_complete_task", status: "awaiting_approval")], error: nil)
        #expect(reply.awaitsApproval)
    }

    @Test func missingToolsAreReportedWithoutRunning() {
        #expect(throws: ICMRoutingError.self) {
            try ConsoleBrainService.ask("hi", vaultURL: URL(fileURLWithPath: "/nonexistent/Projects", isDirectory: true))
        }
    }
}
