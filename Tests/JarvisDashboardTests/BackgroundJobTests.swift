import Foundation
import Testing
@testable import JarvisDashboard

struct BackgroundJobTests {
    private func write(_ jobs: [String], to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, json) in jobs.enumerated() {
            try json.write(to: directory.appendingPathComponent("\(index).json"), atomically: true, encoding: .utf8)
        }
        try "not json".write(to: directory.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
    }

    @Test func readsJobsMarksDeadProcessesStoppedAndHidesOldFinishedOnes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jobs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try write([
            #"{"id":"a","title":"Eval: bonsai-2:9b","status":"running","done":12,"total":50,"detail":"route-12 passed","started_at":"2026-10-29T04:00:00Z","updated_at":"2026-10-29T04:30:00Z","pid":111}"#,
            #"{"id":"b","title":"Crashed eval","status":"running","done":3,"total":50,"started_at":"2026-10-29T03:00:00Z","updated_at":"2026-10-29T03:10:00Z","pid":222}"#,
            #"{"id":"c","title":"Yesterday's refresh","status":"done","done":1,"total":1,"started_at":"2026-10-27T03:00:00Z","updated_at":"2026-10-27T03:01:00Z"}"#,
        ], to: directory)

        let loaded = BackgroundJob.load(from: directory, isAlive: { $0 == 111 })
        let now = ISO8601DateFormatter().date(from: "2026-10-29T05:00:00Z")!
        let visible = BackgroundJob.visible(loaded, now: now)

        #expect(visible.map(\.id) == ["a", "b"])
        #expect(visible[0].isRunning && visible[0].fraction == 0.24)
        #expect(visible[1].isStopped && !visible[1].isRunning)
    }
}
