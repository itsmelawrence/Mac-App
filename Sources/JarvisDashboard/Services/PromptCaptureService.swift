import Foundation

/// Files queued agent prompts into the vault by running the capture hook's `--drain`.
///
/// Codex and Claude Code hooks only write prompts to a private queue in /private/tmp.
/// Filing them needs vault access: launchd jobs cannot list ~/Documents and can only read
/// files they created, so a drain started by JARVIS shares JARVIS's access instead.
/// While JARVIS is closed, prompts wait in the queue.
enum PromptCaptureService {
    static let hookURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex/hooks/obsidian_prompt_capture.py")
    static let queueURL = URL(fileURLWithPath: "/private/tmp/obsidian-prompt-queue-\(getuid())", isDirectory: true)

    /// Cheap check, so Python only starts when there is something to file.
    static func hasQueuedPrompts(in queue: URL = queueURL) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: queue.path)) ?? []
        return items.contains { $0.hasSuffix(".json") }
    }

    static func runWhileAppIsOpen(interval: Duration = .seconds(15)) async {
        while !Task.isCancelled {
            if hasQueuedPrompts(), FileManager.default.fileExists(atPath: hookURL.path) {
                let result = try? VaultMaintenanceService.run(script: hookURL, arguments: ["--drain"], timeout: 120)
                if let result, result.status != 0 {
                    // The hook records details in the queue's last_error.log; failed items stay queued.
                    NSLog("JARVIS prompt capture: drain exited %d", result.status)
                }
            }
            try? await Task.sleep(for: interval)
        }
    }
}
