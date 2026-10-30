import Foundation
import Security
import UserNotifications

/// A website whose contact form JARVIS reads through its read-only `/api/jarvis/leads` feed.
/// The feed's bearer token lives in Keychain under the source's id, never in this record.
struct LeadSource: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var websiteURL: String
}

/// One contact-form submission. Fields a site does not collect stay nil.
struct Lead: Codable, Identifiable, Equatable, Sendable {
    var sourceID: UUID
    var remoteID: Int
    var name: String
    var email: String
    var message: String
    var subject: String?
    var company: String?
    var service: String?
    var status: String?
    var utmSource: String?
    var utmMedium: String?
    var utmCampaign: String?
    var referrer: String?
    var landingPage: String?
    var submittedAt: Date
    var readAt: Date?

    var id: String { "\(sourceID.uuidString)/\(remoteID)" }
    var isUnread: Bool { readAt == nil }

    /// The subject, the service asked about, or the message's first line.
    var headline: String {
        for candidate in [subject, service] {
            if let candidate, !candidate.trimmingCharacters(in: .whitespaces).isEmpty { return candidate }
        }
        return message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }
}

/// Every lead source and the leads fetched from them; saved as `leads.json` and included in backups.
struct LeadBook: Codable, Equatable, Sendable {
    var sources: [LeadSource] = []
    var leads: [Lead] = []
    /// Sources fetched at least once. A source's first fetch imports its existing leads as read, without notifying.
    var syncedSourceIDs: Set<UUID> = []

    /// The feed is read forwards from the highest id already held.
    func cursor(for sourceID: UUID) -> Int {
        leads.lazy.filter { $0.sourceID == sourceID }.map(\.remoteID).max() ?? 0
    }

    /// Adds fetched leads not already held and returns the ones to announce.
    mutating func absorb(_ fetched: [Lead], from sourceID: UUID, now: Date = .now) -> [Lead] {
        let isFirstSync = !syncedSourceIDs.contains(sourceID)
        var held = Set(leads.map(\.id))
        var added: [Lead] = []
        for var lead in fetched where lead.sourceID == sourceID && held.insert(lead.id).inserted {
            if isFirstSync { lead.readAt = now }
            added.append(lead)
        }
        leads.append(contentsOf: added)
        syncedSourceIDs.insert(sourceID)
        return isFirstSync ? [] : added
    }

    /// Replace takes the backup as is. Merge matches sources and leads by id, keeps the backup's
    /// source details, and keeps a lead read if either side has read it.
    mutating func restore(_ backup: LeadBook, replacing: Bool) {
        guard !replacing else { self = backup; return }
        for source in backup.sources {
            if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source }
            else { sources.append(source) }
        }
        let positions = Dictionary(leads.indices.map { (leads[$0].id, $0) }) { first, _ in first }
        for lead in backup.leads {
            if let index = positions[lead.id] {
                leads[index].readAt = leads[index].readAt ?? lead.readAt
            } else {
                leads.append(lead)
            }
        }
        syncedSourceIDs.formUnion(backup.syncedSourceIDs)
    }
}

/// Reads a site's leads feed. Pages forward with `after_id` until the site reports no more.
struct LeadFeedClient: Sendable {
    static let timeout: TimeInterval = 20
    /// 20 pages of 100 per sync; a larger backlog continues on the next sync.
    static let maxPagesPerSync = 20

    struct Page: Decodable, Sendable {
        struct Entry: Decodable, Sendable {
            let id: Int
            let name: String?
            let email: String?
            let message: String?
            let subject: String?
            let company: String?
            let service: String?
            let status: String?
            let utmSource: String?
            let utmMedium: String?
            let utmCampaign: String?
            let referrer: String?
            let landingPage: String?
            let createdAt: Date?
        }

        let data: [Entry]
        let hasMore: Bool
    }

    enum FeedError: LocalizedError, Equatable {
        case invalidAddress
        case notEnabled
        case tokenRejected
        case http(Int)
        case malformed

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "Enter the site's https address."
            case .notEnabled: "The site has no leads feed. Set JARVIS_LEADS_TOKEN in its environment and redeploy."
            case .tokenRejected: "The site rejected the token. Check it matches JARVIS_LEADS_TOKEN."
            case let .http(status): "The leads feed answered HTTP \(status)."
            case .malformed: "The leads feed sent a response JARVIS could not read."
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = LeadFeedClient.makeSession()) {
        self.session = session
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    /// The feed on the site's own host. https only, because the request carries the token.
    static func feedURL(for websiteURL: String, afterID: Int) -> URL? {
        guard let site = SiteChecker.normalizedURL(from: websiteURL), site.scheme == "https",
              var components = URLComponents(url: site, resolvingAgainstBaseURL: false) else { return nil }
        components.path = "/api/jarvis/leads"
        components.queryItems = [URLQueryItem(name: "after_id", value: String(max(0, afterID)))]
        components.fragment = nil
        return components.url
    }

    static func decode(_ data: Data) throws -> Page {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Page.self, from: data)
        } catch {
            throw FeedError.malformed
        }
    }

    static func leads(from page: Page, sourceID: UUID, now: Date = .now) -> [Lead] {
        page.data.map { entry in
            Lead(
                sourceID: sourceID,
                remoteID: entry.id,
                name: entry.name ?? "",
                email: entry.email ?? "",
                message: entry.message ?? "",
                subject: entry.subject,
                company: entry.company,
                service: entry.service,
                status: entry.status,
                utmSource: entry.utmSource,
                utmMedium: entry.utmMedium,
                utmCampaign: entry.utmCampaign,
                referrer: entry.referrer,
                landingPage: entry.landingPage,
                submittedAt: entry.createdAt ?? now
            )
        }
    }

    func fetchLeads(for source: LeadSource, token: String, after cursor: Int) async throws -> [Lead] {
        var leads: [Lead] = []
        var cursor = cursor
        for _ in 0..<Self.maxPagesPerSync {
            guard let url = Self.feedURL(for: source.websiteURL, afterID: cursor) else { throw FeedError.invalidAddress }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200: break
            case 404: throw FeedError.notEnabled
            case 401, 403: throw FeedError.tokenRejected
            case let status: throw FeedError.http(status)
            }
            let page = try Self.decode(data)
            leads += Self.leads(from: page, sourceID: source.id)
            guard page.hasMore, let last = page.data.last?.id, last > cursor else { break }
            cursor = last
        }
        return leads
    }
}

/// Each source's feed token, one generic-password item per source id.
struct LeadTokenStore: Sendable {
    private let service = "com.skeemadigital.jarvisdashboard.leads"

    func read(for sourceID: UUID) -> String? {
        KeychainCache.read(service: service, account: sourceID.uuidString)
    }

    func save(_ token: String, for sourceID: UUID) throws {
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw KeyStoreError.emptyKey }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeyStoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw KeyStoreError.keychain(status)
        }
        KeychainCache.remember(value, service: service, account: sourceID.uuidString)
    }

    func delete(for sourceID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sourceID.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStoreError.keychain(status)
        }
        KeychainCache.remember(nil, service: service, account: sourceID.uuidString)
    }

    enum KeyStoreError: LocalizedError {
        case emptyKey
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyKey:
                "Enter the feed token before saving."
            case let .keychain(status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
            }
        }
    }
}

/// Fetches every source's leads hourly, for the app's lifetime (window open or not). Hourly rather than
/// more often so the check alone does not keep a hibernating Laravel Cloud app awake.
@MainActor
final class LeadMonitor: ObservableObject {
    static let shared = LeadMonitor(snapshots: .shared)
    static let interval: Duration = .seconds(60 * 60)
    static let notificationsKey = "leads.notifyOnNew"
    /// More new leads than this in one sync arrive as one summary notification.
    static let notificationBurstLimit = 3

    @Published private(set) var book: LeadBook
    @Published private(set) var syncingIDs: Set<UUID> = []
    @Published private(set) var errors: [UUID: String] = [:]
    @Published private(set) var lastSyncAt: [UUID: Date] = [:]

    private let client: LeadFeedClient
    private let tokens: LeadTokenStore
    let fileURL: URL
    private let defaults: UserDefaults
    /// Receives the unread count for state.json; nil in tests.
    private let snapshots: StateSnapshotService?

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JARVIS Dashboard/leads.json")
    }

    init(
        client: LeadFeedClient = LeadFeedClient(),
        tokens: LeadTokenStore = LeadTokenStore(),
        fileURL: URL = LeadMonitor.defaultURL,
        defaults: UserDefaults = .standard,
        snapshots: StateSnapshotService? = nil
    ) {
        self.client = client
        self.tokens = tokens
        self.fileURL = fileURL
        self.defaults = defaults
        self.snapshots = snapshots
        book = Self.load(from: fileURL)
    }

    var sources: [LeadSource] { book.sources }
    var isSyncing: Bool { !syncingIDs.isEmpty }

    /// Newest first; the site's id breaks ties between leads sent in the same second.
    func leads(for sourceID: UUID) -> [Lead] {
        book.leads.filter { $0.sourceID == sourceID }.sorted {
            $0.submittedAt == $1.submittedAt ? $0.remoteID > $1.remoteID : $0.submittedAt > $1.submittedAt
        }
    }

    func unreadCount(for sourceID: UUID? = nil) -> Int {
        book.leads.count { $0.isUnread && (sourceID == nil || $0.sourceID == sourceID) }
    }

    func hasToken(for sourceID: UUID) -> Bool { tokens.read(for: sourceID) != nil }

    func run() async {
        publishSnapshot()
        while !Task.isCancelled {
            await syncAll()
            try? await Task.sleep(for: Self.interval)
        }
    }

    /// After sleep the network takes a moment to return.
    func syncAfterWake() {
        Task {
            try? await Task.sleep(for: .seconds(20))
            await syncAll()
        }
    }

    func syncAll() async {
        for source in book.sources { await sync(source.id) }
    }

    func sync(_ sourceID: UUID) async {
        guard let source = book.sources.first(where: { $0.id == sourceID }), !syncingIDs.contains(sourceID) else { return }
        guard let token = tokens.read(for: sourceID) else {
            errors[sourceID] = "Add this site's feed token in Settings → Connections."
            return
        }
        syncingIDs.insert(sourceID)
        defer { syncingIDs.remove(sourceID) }

        do {
            let fetched = try await client.fetchLeads(for: source, token: token, after: book.cursor(for: sourceID))
            // The source may have been removed while the request ran.
            guard book.sources.contains(where: { $0.id == sourceID }) else { return }
            let fresh = book.absorb(fetched, from: sourceID)
            errors[sourceID] = nil
            lastSyncAt[sourceID] = .now
            save()
            notify(fresh, from: source)
        } catch let error as LeadFeedClient.FeedError {
            errors[sourceID] = error.localizedDescription
        } catch {
            errors[sourceID] = SiteChecker.describe(error)
        }
    }

    // MARK: Sources

    @discardableResult
    func addSource(name: String, websiteURL: String, token: String) throws -> LeadSource {
        let source = try validatedSource(LeadSource(name: name, websiteURL: websiteURL))
        try tokens.save(token, for: source.id)
        book.sources.append(source)
        save()
        Task { await sync(source.id) }
        return source
    }

    /// A nil or empty token keeps the saved one.
    func updateSource(_ id: UUID, name: String, websiteURL: String, token: String?) throws {
        guard let index = book.sources.firstIndex(where: { $0.id == id }) else { return }
        let source = try validatedSource(LeadSource(id: id, name: name, websiteURL: websiteURL))
        if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try tokens.save(token, for: id)
        }
        book.sources[index] = source
        errors[id] = nil
        save()
        Task { await sync(id) }
    }

    /// Removes the source, its token, and the leads fetched from it.
    func removeSource(_ id: UUID) throws {
        try tokens.delete(for: id)
        book.sources.removeAll { $0.id == id }
        book.leads.removeAll { $0.sourceID == id }
        book.syncedSourceIDs.remove(id)
        errors[id] = nil
        lastSyncAt[id] = nil
        save()
    }

    private func validatedSource(_ source: LeadSource) throws -> LeadSource {
        guard LeadFeedClient.feedURL(for: source.websiteURL, afterID: 0) != nil,
              let site = SiteChecker.normalizedURL(from: source.websiteURL) else {
            throw LeadFeedClient.FeedError.invalidAddress
        }
        var source = source
        source.websiteURL = site.absoluteString
        let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
        source.name = name.isEmpty ? site.host() ?? site.absoluteString : name
        return source
    }

    // MARK: Read state

    func setRead(_ lead: Lead, _ read: Bool) {
        guard let index = book.leads.firstIndex(where: { $0.id == lead.id }),
              book.leads[index].isUnread == read else { return }
        book.leads[index].readAt = read ? .now : nil
        save()
    }

    func markAllRead(in sourceID: UUID) {
        let now = Date.now
        for index in book.leads.indices where book.leads[index].sourceID == sourceID && book.leads[index].isUnread {
            book.leads[index].readAt = now
        }
        save()
    }

    // MARK: Backup

    func restore(_ backup: LeadBook, replacing: Bool) {
        book.restore(backup, replacing: replacing)
        save()
    }

    // MARK: Storage and notifications

    private func notify(_ leads: [Lead], from source: LeadSource) {
        guard !leads.isEmpty, defaults.object(forKey: Self.notificationsKey) as? Bool ?? true else { return }
        var notifications: [UNMutableNotificationContent] = []
        if leads.count > Self.notificationBurstLimit {
            let content = UNMutableNotificationContent()
            content.title = "\(leads.count) new leads from \(source.name)"
            content.body = leads.map(\.name).filter { !$0.isEmpty }.prefix(5).joined(separator: ", ")
            notifications.append(content)
        } else {
            for lead in leads {
                let content = UNMutableNotificationContent()
                content.title = "New lead from \(source.name)"
                content.body = [lead.name, lead.headline].filter { !$0.isEmpty }.joined(separator: " · ")
                notifications.append(content)
            }
        }
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            for content in notifications {
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: "lead-\(UUID().uuidString)", content: content, trigger: nil))
            }
        }
    }

    private func publishSnapshot() {
        snapshots?.recordLeads(unread: unreadCount())
    }

    private func save() {
        publishSnapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(book) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load(from url: URL) -> LeadBook {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let book = try? decoder.decode(LeadBook.self, from: data) else { return LeadBook() }
        return book
    }
}
