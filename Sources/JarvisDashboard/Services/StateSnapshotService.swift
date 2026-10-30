import Foundation
import SwiftData

/// What JARVIS knows, as versioned JSON for the assistant's read-only `app_*` tools
/// (`.tools/jarvis_mcp`). The logic stays here in Swift; the tools only read the file.
///
/// Tasks and projects come from the store, site checks from `SiteMonitor`. Weather, quakes, and
/// news exist only once a view has fetched them, so each section carries its own `as_of`: a
/// section nobody has refreshed yet is absent rather than invented.
struct StateSnapshot: Codable, Equatable {
    struct Store: Codable, Equatable {
        var asOf: Date
        var tasks: [TaskEntry]
        var projects: [ProjectEntry]
    }

    struct TaskEntry: Codable, Equatable {
        var id: UUID
        var title: String
        var priority: String
        var due: Date?
        var isCompleted: Bool
        var isOverdue: Bool
        var isDueToday: Bool
        var isBlocked: Bool
        var blockedReason: String?
        var projectId: UUID?
        var project: String?
    }

    struct ProjectEntry: Codable, Equatable {
        var id: UUID
        var name: String
        var client: String
        var type: String
        var status: String
        var priority: String
        var mode: String
        var progress: Double
        var nextAction: String
        var due: Date?
        var updatedAt: Date
        var isArchived: Bool
        var repositoryPath: String?
        /// Matches the project's `SiteEntry.siteId` when it has a website.
        var monitoringSiteId: String?
        var openTasks: Int
    }

    struct Briefing: Codable, Equatable {
        var asOf: Date
        var text: String
    }

    struct Sites: Codable, Equatable {
        var asOf: Date
        var items: [SiteEntry]
    }

    struct SiteEntry: Codable, Equatable {
        /// The project's ID: each project has at most one website.
        var siteId: String
        var name: String
        var url: String
        var projectId: UUID?
        var project: String?
        var state: String
        var needsAttention: Bool
        var lastCheck: Date?
        var statusCode: Int?
        var responseMs: Int?
        var error: String?
        var downSince: Date?
        /// 30-day uptime, as a percentage.
        var uptimePercent: Double?
    }

    struct Intelligence: Codable, Equatable {
        struct Alert: Codable, Equatable {
            var title: String
            var detail: String
            var severity: String
            var kind: String
            var occurredAt: Date
            var source: String
        }

        struct Weather: Codable, Equatable {
            var location: String
            var temperatureC: Double
            var feelsLikeC: Double
            var condition: String
            var rainProbability: Int
        }

        struct Earthquake: Codable, Equatable {
            var magnitude: Double
            var place: String
            var occurredAt: Date
            var severity: String
        }

        struct Headline: Codable, Equatable {
            var title: String
            var source: String
            var category: String
            var publishedAt: Date?
            var link: URL
        }

        var asOf: Date
        var alerts: [Alert]
        var weather: [Weather]
        var earthquakes: [Earthquake]
        var headlines: [Headline]
    }

    var schema = StateSnapshotService.schemaVersion
    var appVersion: String
    var asOf: Date
    var store: Store?
    var briefing: Briefing?
    var sites: Sites?
    var intelligence: Intelligence?
}

@MainActor
final class StateSnapshotService {
    nonisolated static let schemaVersion = 1
    static let shared = StateSnapshotService()
    static let headlineLimit = 20

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JARVIS Dashboard/state.json")
    }

    let fileURL: URL
    private let appVersion: String
    private let writeDelay: Duration
    private var store: StateSnapshot.Store?
    private var sites: [UUID: SiteRecord]?
    private var sitesAsOf: Date?
    private var primaryWeather: WeatherSnapshot?
    private var earthquakes: [EarthquakeEvent] = []
    private var intelligence: StateSnapshot.Intelligence?
    private var unreadLeads = 0
    private var pendingWrite: Task<Void, Never>?

    init(
        fileURL: URL = StateSnapshotService.defaultURL,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
        writeDelay: Duration = .seconds(1)
    ) {
        self.fileURL = fileURL
        self.appVersion = appVersion
        self.writeDelay = writeDelay
    }

    // MARK: Inputs

    /// Re-reads tasks and projects. The coordinator calls this on launch, on each save, and every minute,
    /// so overdue and due-today flags stay current.
    func refreshStore(context: ModelContext, now: Date = .now) {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let projects = (try? context.fetch(FetchDescriptor<ProjectItem>())) ?? []
        recordStore(tasks: tasks, projects: projects, now: now)
    }

    func recordStore(tasks: [TaskItem], projects: [ProjectItem], now: Date = .now, calendar: Calendar = .current) {
        let names = Dictionary(projects.map { ($0.id, $0.name) }) { first, _ in first }
        store = StateSnapshot.Store(
            asOf: now,
            tasks: TaskQueueEngine.sorted(tasks, now: now).map { task in
                StateSnapshot.TaskEntry(
                    id: task.id, title: task.title, priority: task.priority.title.lowercased(), due: task.dueDate,
                    isCompleted: task.isCompleted,
                    isOverdue: TaskQueueEngine.matches(task, scope: .overdue, now: now, calendar: calendar),
                    isDueToday: TaskQueueEngine.matches(task, scope: .today, now: now, calendar: calendar),
                    isBlocked: TaskQueueEngine.matches(task, scope: .blocked, now: now, calendar: calendar),
                    blockedReason: task.blockedReason.isEmpty ? nil : task.blockedReason,
                    projectId: task.projectID, project: task.projectID.flatMap { names[$0] })
            },
            projects: projects.sorted { $0.updatedAt > $1.updatedAt }.map { project in
                StateSnapshot.ProjectEntry(
                    id: project.id, name: project.name, client: project.client, type: project.type,
                    status: project.status.rawValue, priority: project.priority.rawValue, mode: project.mode.rawValue,
                    progress: project.progress, nextAction: project.nextAction, due: project.dueDate,
                    updatedAt: project.updatedAt, isArchived: project.isArchived,
                    repositoryPath: project.repositoryPath.isEmpty ? nil : project.repositoryPath,
                    monitoringSiteId: project.hasWebsite ? project.id.uuidString : nil,
                    openTasks: tasks.count { $0.projectID == project.id && !$0.isCompleted })
            })
        scheduleWrite()
    }

    /// Site check history, keyed by project ID.
    func recordSites(_ sites: [UUID: SiteRecord], now: Date = .now) {
        self.sites = sites
        sitesAsOf = now
        scheduleWrite()
    }

    /// Only the count of unread leads; names and messages stay out of state.json.
    func recordLeads(unread: Int) {
        guard unread != unreadLeads else { return }
        unreadLeads = unread
        scheduleWrite()
    }

    /// The weather and quakes behind Today's briefing.
    func recordConditions(weather: WeatherSnapshot?, earthquakes: [EarthquakeEvent]) {
        if let weather { primaryWeather = weather }
        self.earthquakes = earthquakes
        scheduleWrite()
    }

    func recordIntelligence(
        alerts: [IntelligenceAlert], weather: [WeatherSnapshot], earthquakes: [EarthquakeEvent],
        news: [NewsSource.Category: [NewsArticle]], now: Date = .now
    ) {
        let headlines = news.flatMap { category, articles in articles.map { (category, $0) } }
            .sorted { ($0.1.publishedAt ?? .distantPast) > ($1.1.publishedAt ?? .distantPast) }
            .prefix(Self.headlineLimit)
        intelligence = StateSnapshot.Intelligence(
            asOf: now,
            alerts: alerts.sorted { $0.severity > $1.severity }.map {
                .init(title: $0.title, detail: $0.detail, severity: $0.severity.title.lowercased(),
                      kind: $0.kind.rawValue, occurredAt: $0.occurredAt, source: $0.source)
            },
            weather: weather.sorted { $0.locationName < $1.locationName }.map {
                .init(location: $0.locationName, temperatureC: $0.temperature, feelsLikeC: $0.apparentTemperature,
                      condition: $0.condition, rainProbability: $0.precipitationProbability)
            },
            earthquakes: earthquakes.sorted { $0.occurredAt > $1.occurredAt }.map {
                .init(magnitude: $0.magnitude, place: $0.place, occurredAt: $0.occurredAt, severity: $0.severity)
            },
            headlines: headlines.map { category, article in
                .init(title: article.title, source: article.sourceName, category: category.rawValue,
                      publishedAt: article.publishedAt, link: article.link)
            })
        scheduleWrite()
    }

    // MARK: Output

    /// The briefing is composed exactly as Today composes it, from the latest inputs.
    func snapshot(now: Date = .now) -> StateSnapshot {
        var briefing: StateSnapshot.Briefing?
        if let store {
            let pending = store.tasks.filter { !$0.isCompleted }
            let checked = store.projects.filter { !$0.isArchived }.compactMap { project in
                sites?[project.id].map { (project.name, SiteHealth.evaluate(record: $0, hasWebsite: true).state) }
            }
            let text = BriefingComposer().compose(BriefingInput(
                pendingTaskCount: pending.count,
                overdueTaskCount: pending.count(where: \.isOverdue),
                activeProjectCount: store.projects.count { !$0.isArchived && $0.status != ProjectStatus.completed.rawValue },
                weather: primaryWeather,
                significantEarthquakeCount: earthquakes.count { $0.magnitude >= 4.5 },
                downSiteNames: checked.filter { $0.1 == .down }.map(\.0),
                slowSiteNames: checked.filter { $0.1 == .slow }.map(\.0),
                newLeadCount: unreadLeads), date: now)
            briefing = StateSnapshot.Briefing(asOf: now, text: text)
        }
        var siteSection: StateSnapshot.Sites?
        if let sites, let sitesAsOf {
            let projects = Dictionary((store?.projects ?? []).map { ($0.id, $0) }) { first, _ in first }
            siteSection = StateSnapshot.Sites(asOf: sitesAsOf, items: sites.map { id, record in
                let project = projects[id]
                let health = SiteHealth.evaluate(record: record, hasWebsite: true)
                let last = record.lastCheck
                return StateSnapshot.SiteEntry(
                    siteId: id.uuidString, name: project?.name ?? record.url, url: record.url,
                    projectId: project?.id, project: project?.name,
                    state: health.label, needsAttention: health.needsAttention,
                    lastCheck: last?.checkedAt, statusCode: last?.statusCode, responseMs: last?.responseMilliseconds,
                    error: last?.error, downSince: health.downSince,
                    uptimePercent: record.uptime.map { ($0 * 10_000).rounded() / 100 })
            }.sorted { ($0.needsAttention ? 0 : 1, $0.name) < ($1.needsAttention ? 0 : 1, $1.name) })
        }
        return StateSnapshot(appVersion: appVersion, asOf: now, store: store, briefing: briefing,
                             sites: siteSection, intelligence: intelligence)
    }

    static func encode(_ snapshot: StateSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Atomic, and readable only by this user: it names clients and sites.
    func writeNow(now: Date = .now) throws {
        pendingWrite?.cancel()
        pendingWrite = nil
        let data = try Self.encode(snapshot(now: now))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Bursts of changes (a refresh records several sections) become one write.
    private func scheduleWrite() {
        pendingWrite?.cancel()
        let delay = writeDelay
        pendingWrite = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            try? self?.writeNow()
        }
    }
}
