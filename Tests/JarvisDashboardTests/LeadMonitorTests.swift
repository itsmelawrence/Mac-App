import Foundation
import SwiftData
import Testing
@testable import JarvisDashboard

extension LeadMonitor {
    /// A monitor on a throwaway file, so tests never touch the real leads.json or state.json.
    static func temporary(session: URLSession = LeadFeedClient.makeSession(), defaults: UserDefaults? = nil) -> LeadMonitor {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("leads-\(UUID().uuidString).json")
        let suite = UserDefaults(suiteName: "LeadMonitorTests.\(UUID().uuidString)")!
        // Notifications need an app bundle; the test runner has none.
        suite.set(false, forKey: notificationsKey)
        return LeadMonitor(client: LeadFeedClient(session: session), fileURL: url, defaults: defaults ?? suite)
    }
}

private func lead(_ id: Int, source: UUID, readAt: Date? = nil) -> Lead {
    Lead(sourceID: source, remoteID: id, name: "Lead \(id)", email: "lead\(id)@example.com",
         message: "Hello \(id)", submittedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(id)), readAt: readAt)
}

struct LeadFeedTests {
    @Test func feedURLUsesTheSiteHostOverHTTPSOnly() {
        #expect(LeadFeedClient.feedURL(for: "example.com", afterID: 12)?.absoluteString
                == "https://example.com/api/jarvis/leads?after_id=12")
        #expect(LeadFeedClient.feedURL(for: "https://www.example.com/contact#form", afterID: -3)?.absoluteString
                == "https://www.example.com/api/jarvis/leads?after_id=0")
        // The token would travel in the clear.
        #expect(LeadFeedClient.feedURL(for: "http://example.com", afterID: 0) == nil)
        #expect(LeadFeedClient.feedURL(for: "not a site", afterID: 0) == nil)
    }

    @Test func pagesDecodeFromEitherSitesFields() throws {
        let source = UUID()
        let json = """
        {"data": [
          {"id": 4, "name": "Jane", "email": "jane@example.com", "subject": null, "message": "Hi there\\nSecond line",
           "created_at": "2026-10-30T07:15:00Z"},
          {"id": 9, "name": "Sam", "email": "sam@company.com", "company": "Acme", "service": "Marketing automation",
           "message": "We need follow-up", "status": "new", "utm_source": "linkedin", "landing_page": "/",
           "created_at": "2026-10-30T08:00:00Z"}
        ], "has_more": true}
        """
        let page = try LeadFeedClient.decode(Data(json.utf8))
        #expect(page.hasMore)
        let leads = LeadFeedClient.leads(from: page, sourceID: source)
        #expect(leads.map(\.remoteID) == [4, 9])
        #expect(leads[0].headline == "Hi there")
        #expect(leads[0].submittedAt == Date(timeIntervalSince1970: 1_793_344_500))
        #expect(leads[1].headline == "Marketing automation")
        #expect(leads[1].utmSource == "linkedin")
        #expect(leads.allSatisfy { $0.sourceID == source && $0.isUnread })
    }

    @Test func malformedPagesAreRejected() {
        #expect(throws: LeadFeedClient.FeedError.malformed) { try LeadFeedClient.decode(Data("<html>".utf8)) }
    }
}

struct LeadBookTests {
    @Test func firstSyncImportsQuietlyThenNewLeadsAreAnnounced() {
        let source = UUID()
        var book = LeadBook(sources: [LeadSource(id: source, name: "Site", websiteURL: "https://example.com/")])
        let now = Date(timeIntervalSince1970: 1_900_000_000)

        #expect(book.absorb([lead(1, source: source), lead(2, source: source)], from: source, now: now).isEmpty)
        #expect(book.leads.allSatisfy { $0.readAt == now })
        #expect(book.cursor(for: source) == 2)

        let announced = book.absorb([lead(2, source: source), lead(3, source: source), lead(3, source: source)], from: source)
        #expect(announced.map(\.remoteID) == [3])
        #expect(book.leads.count == 3)
        #expect(book.leads.last?.isUnread == true)
        #expect(book.cursor(for: UUID()) == 0)
    }

    @Test func mergeRestoreKeepsReadStateFromEitherSide() {
        let source = UUID()
        let read = Date(timeIntervalSince1970: 1_900_000_000)
        var current = LeadBook(sources: [LeadSource(id: source, name: "Old name", websiteURL: "https://example.com/")],
                               leads: [lead(1, source: source), lead(2, source: source, readAt: read)],
                               syncedSourceIDs: [source])
        let backup = LeadBook(sources: [LeadSource(id: source, name: "New name", websiteURL: "https://example.com/")],
                              leads: [lead(1, source: source, readAt: read), lead(2, source: source), lead(5, source: source)],
                              syncedSourceIDs: [source])

        var replaced = current
        replaced.restore(backup, replacing: true)
        #expect(replaced == backup)

        current.restore(backup, replacing: false)
        #expect(current.sources.map(\.name) == ["New name"])
        #expect(current.leads.map(\.remoteID) == [1, 2, 5])
        #expect(current.leads.prefix(2).allSatisfy { $0.readAt == read })
    }
}

/// Answers each feed request from `respond`; one test uses it at a time.
private final class StubFeedProtocol: URLProtocol {
    nonisolated(unsafe) static var respond: (URLRequest) -> (Int, String) = { _ in (500, "") }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
struct LeadMonitorTests {
    @Test func syncPagesForwardWithTheTokenAndReportsRejection() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubFeedProtocol.self]
        let monitor = LeadMonitor.temporary(session: URLSession(configuration: configuration))
        defer { try? FileManager.default.removeItem(at: monitor.fileURL) }
        let source = LeadSource(name: "Portfolio", websiteURL: "https://example.com/")
        monitor.restore(LeadBook(sources: [source]), replacing: true)
        // Seeds the token in memory only; the Keychain is never written.
        KeychainCache.remember("secret", service: "com.skeemadigital.jarvisdashboard.leads", account: source.id.uuidString)
        defer { KeychainCache.remember(nil, service: "com.skeemadigital.jarvisdashboard.leads", account: source.id.uuidString) }

        var requests: [URLRequest] = []
        var newest = 2
        StubFeedProtocol.respond = { request in
            requests.append(request)
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer secret" else { return (401, "") }
            let after = Int(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "after_id" }!.value!)!
            // Pages of one, to prove the cursor moves forward.
            guard after < newest else { return (200, #"{"data": [], "has_more": false}"#) }
            let id = after + 1
            return (200, #"{"data": [{"id": \#(id), "name": "Lead \#(id)", "email": "l@example.com", "message": "Hi", "created_at": "2026-10-30T07:15:00Z"}], "has_more": \#(id < newest)}"#)
        }

        await monitor.sync(source.id)
        #expect(requests.map { $0.url!.query! } == ["after_id=0", "after_id=1"])
        #expect(monitor.leads(for: source.id).map(\.remoteID) == [2, 1])
        #expect(monitor.unreadCount() == 0)
        #expect(monitor.errors[source.id] == nil)

        newest = 3
        await monitor.sync(source.id)
        #expect(monitor.unreadCount(for: source.id) == 1)
        let saved = LeadMonitor.load(from: monitor.fileURL)
        #expect(saved.leads.map(\.id) == monitor.book.leads.map(\.id))
        #expect(saved.leads.map(\.isUnread) == [false, false, true])

        KeychainCache.remember("stale", service: "com.skeemadigital.jarvisdashboard.leads", account: source.id.uuidString)
        await monitor.sync(source.id)
        #expect(monitor.errors[source.id] == LeadFeedClient.FeedError.tokenRejected.localizedDescription)
        #expect(monitor.book.leads.count == 3)
    }

    @Test func backupsCarryLeadsAndOlderBackupsLeaveThemAlone() throws {
        let source = UUID()
        let book = LeadBook(sources: [LeadSource(id: source, name: "Portfolio", websiteURL: "https://example.com/")],
                            leads: [lead(1, source: source), lead(2, source: source, readAt: Date(timeIntervalSince1970: 1_900_000_000))],
                            syncedSourceIDs: [source])
        let configuration = ModelConfiguration(schema: JarvisDataStore.schema, isStoredInMemoryOnly: true)
        let context = ModelContext(try JarvisDataStore.makeContainer(configuration: configuration))
        let defaults = try #require(UserDefaults(suiteName: "LeadBackupTests.\(UUID().uuidString)"))
        let original = LeadMonitor.temporary()
        let restored = LeadMonitor.temporary()
        defer {
            try? FileManager.default.removeItem(at: original.fileURL)
            try? FileManager.default.removeItem(at: restored.fileURL)
        }
        original.restore(book, replacing: true)

        let exporter = JarvisBackupService(defaults: defaults, appVersion: "test", leadMonitor: original)
        let importer = JarvisBackupService(defaults: defaults, appVersion: "test", leadMonitor: restored)
        let document = try importer.decode(exporter.encode(exporter.makeDocument(context: context)))
        #expect(document.leads == book)
        #expect(try importer.preview(document, context: context).leads.new == 2)

        try importer.apply(document, mode: .merge, context: context)
        #expect(restored.book == book)

        // A backup made before leads existed decodes, and replacing from it keeps the current leads.
        let legacy = JarvisBackupDocument(schemaVersion: 1, appVersion: "0.2.49", exportedAt: .now,
                                          tasks: [], projects: [], savedLocations: [], preferences: [:])
        let legacyData = try importer.encode(legacy)
        #expect(!String(decoding: legacyData, as: UTF8.self).contains("\"leads\""))
        let decodedLegacy = try importer.decode(legacyData)
        #expect(decodedLegacy.leads == nil)
        try importer.apply(decodedLegacy, mode: .replace, confirmation: "REPLACE", context: context,
                           backupFolder: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        #expect(restored.book == book)
    }

    @Test func backupsWithOrphanedLeadsAreRejected() throws {
        let service = JarvisBackupService(appVersion: "test", leadMonitor: .temporary())
        let document = JarvisBackupDocument(schemaVersion: 1, appVersion: "test", exportedAt: .now,
                                            tasks: [], projects: [], savedLocations: [], preferences: [:],
                                            leads: LeadBook(leads: [lead(1, source: UUID())]))
        #expect(throws: JarvisBackupError.invalidRecord("lead-to-source relationship")) {
            try service.decode(service.encode(document))
        }
    }
}
