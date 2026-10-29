import Foundation
import Testing
@testable import JarvisDashboard

struct SiteMonitorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func check(_ outcome: SiteCheck.Outcome, minutesAgo: Double = 0, error: String? = nil) -> SiteCheck {
        SiteCheck(checkedAt: now.addingTimeInterval(-minutesAgo * 60), outcome: outcome,
                  statusCode: outcome == .failed ? 503 : 200, responseMilliseconds: 200,
                  error: outcome == .failed ? error ?? "HTTP 503" : nil)
    }

    @Test func statusCodesClassifyAsUpSlowOrFailed() {
        #expect(SiteChecker.outcome(statusCode: 200, milliseconds: 300) == .up)
        #expect(SiteChecker.outcome(statusCode: 301, milliseconds: 300) == .up)
        #expect(SiteChecker.outcome(statusCode: 200, milliseconds: 4_000) == .slow)
        // A login wall or bot filter still means the server is answering.
        #expect(SiteChecker.outcome(statusCode: 403, milliseconds: 300) == .up)
        #expect(SiteChecker.outcome(statusCode: 404, milliseconds: 300) == .failed)
        #expect(SiteChecker.outcome(statusCode: 502, milliseconds: 300) == .failed)
        #expect(SiteChecker.outcome(statusCode: nil, milliseconds: 300) == .failed)
    }

    @Test func websiteAddressesAreNormalised() {
        #expect(SiteChecker.normalizedURL(from: " example.com ")?.absoluteString == "https://example.com/")
        #expect(SiteChecker.normalizedURL(from: "HTTP://Shop.Example.com/home")?.absoluteString == "http://shop.example.com/home")
        #expect(SiteChecker.normalizedURL(from: "ftp://example.com") == nil)
        #expect(SiteChecker.normalizedURL(from: "localhost") == nil)
        #expect(SiteChecker.normalizedURL(from: "") == nil)
    }

    @Test func oneFailureRetriesAndTwoConfirmAnOutage() {
        var record = SiteRecord(url: "https://example.com/")
        #expect(record.record(check(.up, minutesAgo: 10), calendar: calendar) == nil)
        #expect(record.record(check(.failed, minutesAgo: 5), calendar: calendar) == nil)
        #expect(SiteHealth.evaluate(record: record, hasWebsite: true).state == .retrying)

        #expect(record.record(check(.failed, minutesAgo: 4), calendar: calendar) == .wentDown(reason: "HTTP 503"))
        let health = SiteHealth.evaluate(record: record, hasWebsite: true)
        #expect(health.state == .down)
        // The outage starts at the first failure, not the confirming one.
        #expect(health.downSince == now.addingTimeInterval(-5 * 60))

        // A third failure must not notify again.
        #expect(record.record(check(.failed, minutesAgo: 3), calendar: calendar) == nil)
        #expect(record.record(check(.up), calendar: calendar) == .recovered(after: 5 * 60))
        #expect(SiteHealth.evaluate(record: record, hasWebsite: true).state == .up)
        #expect(record.outages.count == 1)
        #expect(record.outages[0].end == now)
    }

    @Test func blipThenRecoveryIsNotAnOutage() {
        var record = SiteRecord(url: "https://example.com/")
        record.record(check(.failed, minutesAgo: 1), calendar: calendar)
        #expect(record.record(check(.up), calendar: calendar) == nil)
        #expect(record.outages.isEmpty)
        #expect(record.consecutiveFailures == 0)
    }

    @Test func uptimeCoversThirtyDays() throws {
        var record = SiteRecord(url: "https://example.com/")
        // A failure 40 days ago falls outside the window.
        record.record(check(.failed, minutesAgo: 40 * 24 * 60), calendar: calendar)
        for minutes in stride(from: 30.0, through: 0, by: -10) { record.record(check(.up, minutesAgo: minutes), calendar: calendar) }
        record.record(check(.failed), calendar: calendar)
        #expect(record.days.count == 1)
        #expect(try #require(record.uptime) == 4.0 / 5.0)
    }

    @Test func historyIsCapped() {
        var record = SiteRecord(url: "https://example.com/")
        for index in 0..<(SiteRecord.recentLimit + 10) {
            record.record(check(.up, minutesAgo: Double(SiteRecord.recentLimit + 10 - index)), calendar: calendar)
        }
        #expect(record.recent.count == SiteRecord.recentLimit)
        #expect(record.lastCheck?.checkedAt == now.addingTimeInterval(-60))
    }

    @Test func healthWithoutWebsiteOrChecks() {
        #expect(SiteHealth.evaluate(record: nil, hasWebsite: false).state == .noWebsite)
        #expect(SiteHealth.evaluate(record: nil, hasWebsite: true).state == .awaitingCheck)
        #expect(!SiteHealth.evaluate(record: nil, hasWebsite: true).needsAttention)
    }

    @Test func offlineMacIsNotASiteFailure() {
        let offline = SiteCheck(checkedAt: now, outcome: .failed, error: SiteChecker.describe(URLError(.notConnectedToInternet)))
        #expect(SiteChecker.isLocalNetworkFailure(offline))
        #expect(!SiteChecker.isLocalNetworkFailure(check(.failed)))
    }

    @MainActor
    @Test func recordsSurviveRelaunch() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("site-checks.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var record = SiteRecord(url: "https://example.com/")
        record.record(check(.up), calendar: calendar)
        let id = UUID()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode([id.uuidString: record]).write(to: url)

        #expect(SiteMonitor.load(from: url)[id] == record)
        #expect(SiteMonitor(fileURL: url).records[id] == record)
    }

    @Test func durationsReadNaturally() {
        #expect(SiteHealth.duration(30) == "1 min")
        #expect(SiteHealth.duration(12 * 60) == "12 min")
        #expect(SiteHealth.duration(90 * 60) == "1 h 30 min")
        #expect(SiteHealth.duration(3 * 86_400) == "3 days")
    }
}
