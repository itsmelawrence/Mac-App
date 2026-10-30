import Foundation

/// The local model's answer to one console prompt, as `.tools/console_brain.py` prints it (roadmap 4.2).
struct ConsoleBrainReply: Decodable, Equatable, Sendable {
    struct Call: Decodable, Equatable, Sendable {
        let tool: String
        /// The gate's status for a write tool (`done`, `queued`, `awaiting_approval`, …); nil for reads.
        let status: String?
    }

    let answer: String
    let model: String
    let seconds: Double
    let calls: [Call]
    let error: String?

    /// The tools used, with what the gate did for each write, e.g. "app_list_tasks, app_add_task (queued)".
    var toolsLine: String? {
        guard !calls.isEmpty else { return nil }
        return calls.map { call in call.status.map { "\(call.tool) (\($0))" } ?? call.tool }.joined(separator: ", ")
    }

    var awaitsApproval: Bool { calls.contains { $0.status == "awaiting_approval" } }

    var sourceLine: String {
        "Local model · \(model) · \(seconds.formatted(.number.precision(.fractionLength(0)))) s"
    }
}

/// Asks the local model, through the jarvis tools, about console prompts no built-in command matched.
///
/// The script needs the `mcp` package, so it runs with the jarvis MCP server's own Python, not `/usr/bin/python3`.
/// The prompt goes on standard input. Actions are live and pass the gate as client "console".
enum ConsoleBrainService {
    /// The model can take a minute or two on this Mac; a stuck run is ended here.
    static let timeout: TimeInterval = 300

    static func scriptURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent(".tools/console_brain.py")
    }

    static func pythonURL(vaultURL: URL) -> URL {
        vaultURL.deletingLastPathComponent().appendingPathComponent(".tools/jarvis_mcp/.venv/bin/python")
    }

    /// Blocks; call off the main actor.
    static func ask(_ prompt: String, vaultURL: URL) throws -> ConsoleBrainReply {
        let script = scriptURL(vaultURL: vaultURL)
        let python = pythonURL(vaultURL: vaultURL)
        for file in [script, python] where !FileManager.default.fileExists(atPath: file.path) {
            throw ICMRoutingError.vaultToolsMissing(file.path)
        }
        return try VaultMaintenanceService.runJSON(script: script, arguments: [], input: prompt, timeout: timeout,
                                                   python: python, as: ConsoleBrainReply.self)
    }
}
