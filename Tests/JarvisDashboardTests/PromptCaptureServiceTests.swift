import Foundation
import Testing
@testable import JarvisDashboard

struct PromptCaptureServiceTests {
    @Test func onlyQueuedJSONCountsAsWork() throws {
        let queue = FileManager.default.temporaryDirectory.appendingPathComponent("queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: queue, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: queue) }
        #expect(!PromptCaptureService.hasQueuedPrompts(in: queue))
        for name in ["last_error.log", ".drain.lock", "launchd-stdout.log"] {
            try "x".write(to: queue.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        #expect(!PromptCaptureService.hasQueuedPrompts(in: queue))
        try "{}".write(to: queue.appendingPathComponent("abc.json"), atomically: true, encoding: .utf8)
        #expect(PromptCaptureService.hasQueuedPrompts(in: queue))
        #expect(!PromptCaptureService.hasQueuedPrompts(in: queue.appendingPathComponent("missing")))
    }

    @Test func hungScriptIsTerminatedAtTimeout() throws {
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("hang-\(UUID().uuidString).py")
        defer { try? FileManager.default.removeItem(at: script) }
        try "import time\nprint('started', flush=True)\ntime.sleep(30)\n".write(to: script, atomically: true, encoding: .utf8)
        let started = Date()
        let result = try VaultMaintenanceService.run(script: script, timeout: 1)
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(result.status != 0)
        #expect(result.output.contains("started"))
    }
}
