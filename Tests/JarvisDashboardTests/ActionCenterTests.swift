import Foundation
import Testing
@testable import JarvisDashboard

/// The gate's rules are tested in the vault tools (`.tools/tests/test_actions.py`); these cover JARVIS's side:
/// reading its state, announcing new approvals once, and passing decisions through.
@MainActor
struct ActionCenterTests {
    private func makeStub() throws -> (root: URL, vault: URL, calls: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-actions-\(UUID().uuidString)")
        let vault = root.appendingPathComponent("Projects")
        let calls = root.appendingPathComponent("calls.txt")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".tools"), withIntermediateDirectories: true)
        let script = """
        import json, sys
        with open(\(String(reflecting: calls.path)), "a") as f:
            f.write(" ".join(sys.argv[1:3]) + "\\n")
        if sys.argv[1] == "state":
            print(json.dumps({"pending": [{"id": "20261029T010000-abc123", "action": "note_replace_text", "tier": 2,
                "client": "jarvis-mcp", "summary": "Edit Notes/Resources/Guide.md", "preview": "-old\\n+new",
                "requested_at": "2026-10-29T01:00:00Z", "expires_at": "2026-10-29T01:10:00Z"}],
                "recent": [{"id": "20261029T005900-def456", "action": "hub_append_note", "tier": 1, "status": "done",
                "summary": "Add a note", "undo": True, "requested_at": "2026-10-29T00:59:00Z",
                "updated_at": "2026-10-29T00:59:00Z"}]}))
        elif sys.argv[1] == "approve":
            print(json.dumps({"id": sys.argv[2], "status": "refused", "reason": "the target changed since the request"}))
        else:
            print(json.dumps({"id": sys.argv[2], "status": "undone"}))
        """
        try script.write(to: root.appendingPathComponent(".tools/actions.py"), atomically: true, encoding: .utf8)
        return (root, vault, calls)
    }

    @Test func readsPendingAndRecentAndAnnouncesEachApprovalOnce() async throws {
        let stub = try makeStub()
        defer { try? FileManager.default.removeItem(at: stub.root) }
        var announced: [String] = []
        let center = ActionCenter(vaultURL: { stub.vault }, stateURL: stub.root.appendingPathComponent("state"),
                                  notify: { announced.append($0.id) })
        await center.refresh()
        await center.refresh()

        #expect(center.pending.map(\.tier) == [2])
        #expect(center.pending.first?.preview == "-old\n+new")
        #expect(center.pending.first?.expiresAt == ISO8601DateFormatter().date(from: "2026-10-29T01:10:00Z"))
        #expect(center.recent.first?.canUndo == true)
        #expect(announced == ["20261029T010000-abc123"])
    }

    @Test func decisionsGoToTheGateAndItsAnswerIsShown() async throws {
        let stub = try makeStub()
        defer { try? FileManager.default.removeItem(at: stub.root) }
        let center = ActionCenter(vaultURL: { stub.vault }, stateURL: stub.root.appendingPathComponent("state"), notify: { _ in })

        await center.approve("20261029T010000-abc123")
        #expect(center.message == "Not done: the target changed since the request")
        await center.undo("20261029T005900-def456")
        #expect(center.message == "Undone.")

        let calls = try String(contentsOf: stub.calls, encoding: .utf8).split(separator: "\n")
        #expect(calls.contains("approve 20261029T010000-abc123"))
        #expect(calls.contains("undo 20261029T005900-def456"))
        #expect(center.busy.isEmpty)
    }
}
