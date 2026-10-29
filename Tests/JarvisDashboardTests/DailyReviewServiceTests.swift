import Foundation
import Testing
@testable import JarvisDashboard

/// The review itself is tested in the vault tools (`.tools/tests/test_daily_review.py`); these cover JARVIS's side:
/// when it runs, reading the script's reply, and announcing it once.
@MainActor
struct DailyReviewServiceTests {
    static let reply = """
    {"date": "2026-10-30", "generated_at": "2026-10-30T07:05:00+08:00", "note": "Notes/Areas/Daily review/2026-10-30.md",
     "summary": ["Clinic site is down: check the site first.", "Overdue: Send invoice (due 20 Oct)."],
     "summary_source": "facts", "model": null, "fallback_reason": "the local model isn't running",
     "counts": {"overdue": 1, "due_today": 0, "sites_down": 1, "alerts": 0, "unfinished": 2, "proposals": 1},
     "proposals": [{"id": "20261030T070500-abc123", "status": "awaiting_approval", "summary": "Add task: Look into Clinic site"}]}
    """

    @Test func scriptLivesInToolsFolderBesideTheVault() {
        let vault = URL(fileURLWithPath: "/Users/me/Documents/Main/Projects")
        #expect(DailyReviewService.scriptURL(vaultURL: vault).path == "/Users/me/Documents/Main/.tools/daily_review.py")
    }

    @Test func dueOncePerDayFromSevenOClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Manila"))
        func at(_ hour: Int, day: Int = 30) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: 5))!
        }
        #expect(!DailyReviewService.isDue(lastRunDay: nil, now: at(6), calendar: calendar))
        #expect(DailyReviewService.isDue(lastRunDay: nil, now: at(7), calendar: calendar))
        #expect(DailyReviewService.isDue(lastRunDay: "2026-10-29", now: at(22), calendar: calendar))
        #expect(!DailyReviewService.isDue(lastRunDay: "2026-10-30", now: at(9), calendar: calendar))
        #expect(DailyReviewService.day(at(0, day: 1), calendar: calendar) == "2026-10-01")
    }

    @Test func decodesTheScriptsReply() throws {
        let review = try DailyReview.decoder.decode(DailyReview.self, from: Data(Self.reply.utf8))
        #expect(review.summary.count == 2)
        #expect(review.counts.sitesDown == 1 && review.counts.proposals == 1)
        #expect(review.sourceLine == "Facts only: the local model isn't running")
        #expect(review.proposals.first?.status == "awaiting_approval")
    }

    @Test func runningRecordsTheDayKeepsTheReviewAndAnnouncesItOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("jarvis-review-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let vault = root.appendingPathComponent("Projects")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".tools"), withIntermediateDirectories: true)
        try "print('model warming up')\nprint(\(String(reflecting: Self.reply.replacingOccurrences(of: "\n", with: " "))))\n"
            .write(to: DailyReviewService.scriptURL(vaultURL: vault), atomically: true, encoding: .utf8)
        let defaults = try #require(UserDefaults(suiteName: "daily-review-\(UUID().uuidString)"))
        var announced: [DailyReview] = []
        let service = DailyReviewService(defaults: defaults, stateURL: root, vaultURL: { vault }, notify: { announced.append($0) })

        await service.runNow(announce: true)
        #expect(service.review?.counts.overdue == 1)
        #expect(service.message == nil)
        #expect(announced.count == 1)
        #expect(defaults.string(forKey: DailyReviewService.lastRunKey) == DailyReviewService.day(.now))

        await service.runNow()  // "Run again" from Today: refreshes without another notification
        #expect(announced.count == 1)
    }

    @Test func aMissingScriptIsReportedAndNothingRuns() async throws {
        let defaults = try #require(UserDefaults(suiteName: "daily-review-\(UUID().uuidString)"))
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("no-vault-\(UUID().uuidString)/Projects")
        let service = DailyReviewService(defaults: defaults, stateURL: vault, vaultURL: { vault }, notify: { _ in })
        await service.runNow(announce: true)
        #expect(service.message?.contains("daily_review.py is missing") == true)
        #expect(defaults.string(forKey: DailyReviewService.lastRunKey) == nil)
    }
}
