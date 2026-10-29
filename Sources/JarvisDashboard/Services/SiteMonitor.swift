import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// One request to a project's website.
struct SiteCheck: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable {
        case up
        case slow
        case failed
    }

    var checkedAt: Date
    var outcome: Outcome
    var statusCode: Int?
    var responseMilliseconds: Int?
    var error: String?
}

/// Up/down checks run from this Mac with a plain GET: no monitoring service and nothing installed on the site.
struct SiteChecker: Sendable {
    static let timeout: TimeInterval = 15
    static let slowMilliseconds = 3_000

    private let session: URLSession

    init(session: URLSession = SiteChecker.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        // Some firewalls reject requests without a browser-like user agent.
        configuration.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh) JARVIS-Uptime/1.0"]
        return URLSession(configuration: configuration)
    }

    func check(_ url: URL) async -> SiteCheck {
        let started = Date.now
        do {
            // Headers are enough; cancelling skips downloading the page body.
            let (bytes, response) = try await session.bytes(from: url)
            bytes.task.cancel()
            let milliseconds = Int(Date.now.timeIntervalSince(started) * 1_000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let outcome = Self.outcome(statusCode: statusCode, milliseconds: milliseconds)
            return SiteCheck(
                checkedAt: .now,
                outcome: outcome,
                statusCode: statusCode,
                responseMilliseconds: milliseconds,
                error: outcome == .failed ? statusCode.map { "HTTP \($0)" } ?? "No HTTP response" : nil
            )
        } catch {
            return SiteCheck(checkedAt: .now, outcome: .failed, error: Self.describe(error))
        }
    }

    /// 2xx and 3xx are up. 401, 403 and 429 mean the server answered but refused us (a login wall or a
    /// bot filter), so the site is still up. Anything else is a failure.
    static func outcome(statusCode: Int?, milliseconds: Int) -> SiteCheck.Outcome {
        guard let statusCode,
              (200..<400).contains(statusCode) || [401, 403, 429].contains(statusCode) else { return .failed }
        return milliseconds > slowMilliseconds ? .slow : .up
    }

    /// True when the failure is this Mac's connection, not the site. Such checks are not recorded.
    static func isLocalNetworkFailure(_ check: SiteCheck) -> Bool {
        check.error == offlineMessage
    }

    private static let offlineMessage = "This Mac is offline"

    static func describe(_ error: Error) -> String {
        guard let error = error as? URLError else { return error.localizedDescription }
        switch error.code {
        case .timedOut: return "Timed out after \(Int(timeout)) s"
        case .cannotFindHost, .dnsLookupFailed: return "Domain does not resolve"
        case .cannotConnectToHost: return "Connection refused"
        case .networkConnectionLost: return "Connection dropped"
        case .notConnectedToInternet: return offlineMessage
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            return "SSL certificate problem"
        case .httpTooManyRedirects, .redirectToNonExistentLocation: return "Redirect loop"
        default: return error.localizedDescription
        }
    }

    /// Accepts "example.com" or a full URL; nil unless it is an http(s) address with a dotted host.
    static func normalizedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "https://" + trimmed }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        components.scheme = scheme
        components.host = host
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }
}

/// A site's check history: the latest checks, a 30-day daily tally for uptime, and confirmed outages.
struct SiteRecord: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Sendable {
        var day: Date
        var checks: Int
        var failures: Int
    }

    struct Outage: Codable, Equatable, Sendable, Identifiable {
        var start: Date
        var end: Date?
        var reason: String
        var id: Date { start }
    }

    enum Transition: Equatable, Sendable {
        case wentDown(reason: String)
        case recovered(after: TimeInterval)
    }

    static let recentLimit = 50
    static let outageLimit = 20
    static let historyDays = 30
    /// Failures in a row before a site counts as down; one failure is often a blip.
    static let failuresToConfirmDown = 2

    var url: String
    var recent: [SiteCheck] = []
    var days: [Day] = []
    var outages: [Outage] = []
    var consecutiveFailures = 0

    var lastCheck: SiteCheck? { recent.last }
    var openOutage: Outage? { outages.last.flatMap { $0.end == nil ? $0 : nil } }

    /// Share of checks in the last 30 days that succeeded, from 0 to 1; nil before the first check.
    var uptime: Double? {
        let checks = days.reduce(0) { $0 + $1.checks }
        guard checks > 0 else { return nil }
        return Double(checks - days.reduce(0) { $0 + $1.failures }) / Double(checks)
    }

    @discardableResult
    mutating func record(_ check: SiteCheck, calendar: Calendar = .current) -> Transition? {
        recent.append(check)
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }

        let day = calendar.startOfDay(for: check.checkedAt)
        if let index = days.lastIndex(where: { $0.day == day }) {
            days[index].checks += 1
            if check.outcome == .failed { days[index].failures += 1 }
        } else {
            days.append(Day(day: day, checks: 1, failures: check.outcome == .failed ? 1 : 0))
        }
        if let cutoff = calendar.date(byAdding: .day, value: -(Self.historyDays - 1), to: day) {
            days.removeAll { $0.day < cutoff }
        }

        guard check.outcome == .failed else {
            consecutiveFailures = 0
            guard let index = outages.indices.last, outages[index].end == nil else { return nil }
            outages[index].end = check.checkedAt
            return .recovered(after: check.checkedAt.timeIntervalSince(outages[index].start))
        }

        consecutiveFailures += 1
        guard consecutiveFailures == Self.failuresToConfirmDown else { return nil }
        // The outage began at the first failure in this run, not at the confirming one.
        let start = recent[recent.count - Self.failuresToConfirmDown].checkedAt
        let reason = check.error ?? "Unreachable"
        outages.append(Outage(start: start, end: nil, reason: reason))
        if outages.count > Self.outageLimit { outages.removeFirst(outages.count - Self.outageLimit) }
        return .wentDown(reason: reason)
    }
}

/// The verdict shown for a project's website.
struct SiteHealth: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case up
        case slow
        /// One failed check; a retry within a minute confirms or clears it.
        case retrying
        case down
        case awaitingCheck
        case noWebsite
    }

    let state: State
    let lastCheck: SiteCheck?
    let downSince: Date?
    let uptime: Double?

    var label: String {
        switch state {
        case .up: "Up"
        case .slow: "Slow"
        case .retrying: "Retrying"
        case .down: "Down"
        case .awaitingCheck: "Checking…"
        case .noWebsite: "No website"
        }
    }

    var colour: Color {
        switch state {
        case .up: Color(red: 0.24, green: 0.81, blue: 0.56)
        case .slow, .retrying: Color(red: 0.96, green: 0.65, blue: 0.14)
        case .down: Color(red: 0.94, green: 0.33, blue: 0.31)
        case .awaitingCheck, .noWebsite: .secondary
        }
    }

    var systemImage: String {
        switch state {
        case .up: "checkmark.circle.fill"
        case .slow: "tortoise.fill"
        case .retrying: "arrow.triangle.2.circlepath"
        case .down: "xmark.octagon.fill"
        case .awaitingCheck: "clock"
        case .noWebsite: "globe"
        }
    }

    var sortRank: Int {
        switch state {
        case .down: 0
        case .retrying: 1
        case .slow: 2
        case .awaitingCheck: 3
        case .up: 4
        case .noWebsite: 5
        }
    }

    var needsAttention: Bool { state == .down || state == .slow }

    /// "Up · 240 ms", "Down for 12 min", "HTTP 503 · retrying".
    var detail: String {
        switch state {
        case .up, .slow:
            return lastCheck?.responseMilliseconds.map { "\(label) · \($0) ms" } ?? label
        case .retrying:
            return "\(lastCheck?.error ?? "Failed") · retrying"
        case .down:
            guard let downSince else { return label }
            return "Down for \(Self.duration(Date.now.timeIntervalSince(downSince)))"
        case .awaitingCheck, .noWebsite:
            return label
        }
    }

    static func evaluate(record: SiteRecord?, hasWebsite: Bool) -> SiteHealth {
        guard hasWebsite else { return SiteHealth(state: .noWebsite, lastCheck: nil, downSince: nil, uptime: nil) }
        guard let record, let last = record.lastCheck else {
            return SiteHealth(state: .awaitingCheck, lastCheck: nil, downSince: nil, uptime: nil)
        }
        let state: State
        if let outage = record.openOutage {
            return SiteHealth(state: .down, lastCheck: last, downSince: outage.start, uptime: record.uptime)
        }
        switch last.outcome {
        case .up: state = .up
        case .slow: state = .slow
        case .failed: state = .retrying
        }
        return SiteHealth(state: state, lastCheck: last, downSince: nil, uptime: record.uptime)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 48 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        return "\(hours / 24) days"
    }
}

/// Runs the checks for every project with a website, for the app's lifetime (window open or not).
@MainActor
final class SiteMonitor: ObservableObject {
    static let shared = SiteMonitor()
    static let interval: Duration = .seconds(5 * 60)
    static let retryDelay: Duration = .seconds(60)
    static let notificationsKey = "sites.notifyOnChange"

    @Published private(set) var records: [UUID: SiteRecord] = [:]
    @Published private(set) var checkingIDs: Set<UUID> = []
    @Published private(set) var lastPassAt: Date?
    @Published private(set) var isOffline = false

    private let checker: SiteChecker
    private let fileURL: URL
    private let defaults: UserDefaults
    private var context: ModelContext?

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JARVIS Dashboard/site-checks.json")
    }

    init(checker: SiteChecker = SiteChecker(), fileURL: URL = SiteMonitor.defaultURL, defaults: UserDefaults = .standard) {
        self.checker = checker
        self.fileURL = fileURL
        self.defaults = defaults
        records = Self.load(from: fileURL)
    }

    var isChecking: Bool { !checkingIDs.isEmpty }

    func health(for project: ProjectItem) -> SiteHealth {
        SiteHealth.evaluate(record: records[project.id], hasWebsite: project.hasWebsite)
    }

    func record(for project: ProjectItem) -> SiteRecord? { records[project.id] }

    /// Names of non-archived projects whose site is down, and those that are slow, for the briefing.
    func briefingSites(for projects: [ProjectItem]) -> (down: [String], slow: [String]) {
        let active = projects.filter { $0.hasWebsite && !$0.isArchived }
        return (active.filter { health(for: $0).state == .down }.map(\.name),
                active.filter { health(for: $0).state == .slow }.map(\.name))
    }

    func attach(_ context: ModelContext) {
        self.context = context
        StateSnapshotService.shared.recordSites(records)
    }

    /// Checks every 5 minutes, or after a minute while a failure awaits confirmation.
    func run() async {
        while !Task.isCancelled {
            await checkAll()
            let retrying = records.values.contains { $0.consecutiveFailures > 0 && $0.openOutage == nil }
            try? await Task.sleep(for: retrying ? Self.retryDelay : Self.interval)
        }
    }

    /// After sleep the network takes a moment to return; checking at once would report every site down.
    func checkAfterWake() {
        Task {
            try? await Task.sleep(for: .seconds(20))
            await checkAll()
        }
    }

    func checkAll() async {
        await check(projects: monitoredProjects())
    }

    func check(_ project: ProjectItem) async {
        await check(projects: [project])
    }

    private func monitoredProjects() -> [ProjectItem] {
        guard let context, let projects = try? context.fetch(FetchDescriptor<ProjectItem>()) else { return [] }
        // Forget sites whose project was deleted or no longer has a website.
        let kept = Set(projects.filter(\.hasWebsite).map(\.id))
        if records.keys.contains(where: { !kept.contains($0) }) {
            records = records.filter { kept.contains($0.key) }
            save()
        }
        return projects.filter { $0.hasWebsite && !$0.isArchived }
    }

    private func check(projects: [ProjectItem]) async {
        let targets: [(id: UUID, name: String, url: URL)] = projects.compactMap { project in
            guard !checkingIDs.contains(project.id),
                  let url = SiteChecker.normalizedURL(from: project.monitoringWebsiteURL) else { return nil }
            return (project.id, project.name, url)
        }
        guard !targets.isEmpty else { return }
        checkingIDs.formUnion(targets.map(\.id))
        defer { checkingIDs.subtract(targets.map(\.id)) }

        let checker = checker
        let results = await withTaskGroup(of: (UUID, SiteCheck).self) { group in
            for target in targets {
                group.addTask { (target.id, await checker.check(target.url)) }
            }
            var results: [UUID: SiteCheck] = [:]
            for await (id, check) in group { results[id] = check }
            return results
        }

        // When this Mac is offline every site fails; that says nothing about the sites.
        isOffline = !results.isEmpty && results.values.allSatisfy(SiteChecker.isLocalNetworkFailure)
        guard !isOffline else { return }

        for target in targets {
            guard let check = results[target.id], !SiteChecker.isLocalNetworkFailure(check) else { continue }
            var record = records[target.id] ?? SiteRecord(url: target.url.absoluteString)
            if record.url != target.url.absoluteString { record = SiteRecord(url: target.url.absoluteString) }
            if let transition = record.record(check) { notify(transition, name: target.name, url: target.url) }
            records[target.id] = record
        }
        lastPassAt = .now
        save()
        StateSnapshotService.shared.recordSites(records)
    }

    private func notify(_ transition: SiteRecord.Transition, name: String, url: URL) {
        guard defaults.object(forKey: Self.notificationsKey) as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        switch transition {
        case let .wentDown(reason):
            content.title = "\(name) is down"
            content.body = "\(url.host() ?? url.absoluteString) · \(reason)"
        case let .recovered(after):
            content.title = "\(name) is back up"
            content.body = "Recovered after \(SiteHealth.duration(after))."
        }
        content.sound = .default
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            try? await center.add(UNNotificationRequest(identifier: "site-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let keyed = Dictionary(uniqueKeysWithValues: records.map { ($0.key.uuidString, $0.value) })
        guard let data = try? encoder.encode(keyed) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load(from url: URL) -> [UUID: SiteRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let keyed = try? decoder.decode([String: SiteRecord].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: keyed.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } })
    }
}
