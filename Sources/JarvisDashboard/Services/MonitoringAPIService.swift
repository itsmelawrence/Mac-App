import Foundation

struct MonitoringAPISummary: Equatable, Sendable {
    struct Statuses: Equatable, Sendable {
        let up: Int
        let down: Int
        let degraded: Int
        let unknown: Int
        let maintenance: Int
    }

    let sites: Int
    let statuses: Statuses
    let openIncidents: Int
    let openFindings: Int
}

struct MonitoringSiteRegistration: Equatable, Sendable {
    let id: String
    let name: String
    let url: String
    let platform: MonitoringPlatform
    let ingestToken: String
}

struct MonitoringSite: Equatable, Sendable {
    let id: String
    let name: String
    let url: String
    let platform: MonitoringPlatform
    let status: MonitoringSiteStatus
    let lastCheckAt: Date?
    let lastStatusCode: Int?
    let lastResponseMilliseconds: Int?
    let lastHeartbeatAt: Date?
    let lastReportedAt: Date?
    let sslExpiresAt: Date?
    let uptime30DayPercent: Double?
    let openIncidentsCount: Int
    let openFindingsCount: Int
    let latestSnapshot: MonitoringSnapshot?
    let incidents: [MonitoringIncident]
    let findings: [MonitoringFinding]

    init(
        id: String,
        name: String,
        url: String,
        platform: MonitoringPlatform,
        status: MonitoringSiteStatus = .unknown,
        lastCheckAt: Date? = nil,
        lastStatusCode: Int? = nil,
        lastResponseMilliseconds: Int? = nil,
        lastHeartbeatAt: Date? = nil,
        lastReportedAt: Date? = nil,
        sslExpiresAt: Date? = nil,
        uptime30DayPercent: Double? = nil,
        openIncidentsCount: Int = 0,
        openFindingsCount: Int = 0,
        latestSnapshot: MonitoringSnapshot? = nil,
        incidents: [MonitoringIncident] = [],
        findings: [MonitoringFinding] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.platform = platform
        self.status = status
        self.lastCheckAt = lastCheckAt
        self.lastStatusCode = lastStatusCode
        self.lastResponseMilliseconds = lastResponseMilliseconds
        self.lastHeartbeatAt = lastHeartbeatAt
        self.lastReportedAt = lastReportedAt
        self.sslExpiresAt = sslExpiresAt
        self.uptime30DayPercent = uptime30DayPercent
        self.openIncidentsCount = openIncidentsCount
        self.openFindingsCount = openFindingsCount
        self.latestSnapshot = latestSnapshot
        self.incidents = incidents
        self.findings = findings
    }
}

enum MonitoringSiteStatus: String, Equatable, Sendable {
    case up
    case down
    case degraded
    case unknown
    case maintenance
}

struct MonitoringSnapshot: Equatable, Sendable {
    let checkedAt: Date?
    let phpVersion: String?
    let phpSupported: Bool?
    let pendingUpdateCount: Int
    let components: [MonitoringComponent]
    let notCovered: [String]
    let siteHealth: [MonitoringSiteHealthCheck]
    let applicationName: String?
    let applicationVersion: String?
    let environment: String?
}

struct MonitoringComponent: Equatable, Identifiable, Sendable {
    var id: String { "\(ecosystem):\(name)" }
    let ecosystem: String
    let name: String
    let version: String
    let latestVersion: String?
    let updateAvailable: Bool?
    let isDirect: Bool?
    let isDevelopment: Bool?
}

struct MonitoringSiteHealthCheck: Equatable, Identifiable, Sendable {
    var id: String { key }
    let key: String
    let label: String
    let status: String
    let message: String?
}

struct MonitoringIncident: Equatable, Identifiable, Sendable {
    let id: String
    let type: String
    let startedAt: Date?
    let endedAt: Date?
    let durationSeconds: Int?
}

struct MonitoringFinding: Equatable, Identifiable, Sendable {
    let id: String
    let componentType: String
    let slug: String
    let title: String
    let severity: String
    let fixedIn: String?
    let status: String
    let referenceURL: String?
}

struct MonitoringAPIService: Sendable {
    static let defaultBaseURL = "https://jarvis-monitoring-api-production-lhpmbl.laravel.cloud"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func summary(baseURLText: String, token: String) async throws -> MonitoringAPISummary {
        let request = try makeSummaryRequest(baseURLText: baseURLText, token: token)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonitoringAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try parseSummary(data: data)
        case 401:
            throw MonitoringAPIError.unauthorised
        case 403:
            throw MonitoringAPIError.forbidden
        default:
            throw MonitoringAPIError.serverStatus(httpResponse.statusCode)
        }
    }

    func registerSite(
        baseURLText: String,
        adminToken: String,
        name: String,
        websiteURLText: String,
        platform: MonitoringPlatform
    ) async throws -> MonitoringSiteRegistration {
        let request = try makeRegisterSiteRequest(
            baseURLText: baseURLText,
            adminToken: adminToken,
            name: name,
            websiteURLText: websiteURLText,
            platform: platform
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonitoringAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try parseSiteRegistration(data: data)
        case 401:
            throw MonitoringAPIError.unauthorised
        case 403:
            throw MonitoringAPIError.adminRequired
        case 422:
            throw MonitoringAPIError.invalidSite
        default:
            throw MonitoringAPIError.serverStatus(httpResponse.statusCode)
        }
    }

    func updateSite(
        baseURLText: String,
        adminToken: String,
        siteID: String,
        name: String,
        websiteURLText: String,
        platform: MonitoringPlatform
    ) async throws -> MonitoringSite {
        let request = try makeUpdateSiteRequest(
            baseURLText: baseURLText,
            adminToken: adminToken,
            siteID: siteID,
            name: name,
            websiteURLText: websiteURLText,
            platform: platform
        )
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonitoringAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try parseSite(data: data)
        case 401:
            throw MonitoringAPIError.unauthorised
        case 403:
            throw MonitoringAPIError.adminRequired
        case 422:
            throw MonitoringAPIError.invalidSite
        default:
            throw MonitoringAPIError.serverStatus(httpResponse.statusCode)
        }
    }

    func existingSite(
        baseURLText: String,
        readToken: String,
        websiteURLText: String
    ) async throws -> MonitoringSite? {
        let websiteURL = try normalizedWebsiteURL(from: websiteURLText).absoluteString
        let request = try makeSitesRequest(baseURLText: baseURLText, token: readToken)
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonitoringAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try parseSites(data: data).first { $0.url == websiteURL }
        case 401:
            throw MonitoringAPIError.unauthorised
        case 403:
            throw MonitoringAPIError.forbidden
        default:
            throw MonitoringAPIError.serverStatus(httpResponse.statusCode)
        }
    }

    func sites(baseURLText: String, readToken: String) async throws -> [MonitoringSite] {
        let request = try makeSitesRequest(baseURLText: baseURLText, token: readToken)
        let (data, response) = try await session.data(for: request)
        try validateReadResponse(response)
        return try parseSites(data: data)
    }

    func site(baseURLText: String, readToken: String, siteID: String) async throws -> MonitoringSite {
        let baseURL = try normalizedBaseURL(from: baseURLText)
        let trimmedToken = readToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw MonitoringAPIError.missingToken }

        let url = baseURL.appending(path: "api/v1/sites/\(siteID)")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("JARVIS-Dashboard/0.3", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        try validateReadResponse(response)
        return try parseSite(data: data)
    }

    private func validateReadResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonitoringAPIError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300: return
        case 401: throw MonitoringAPIError.unauthorised
        case 403: throw MonitoringAPIError.forbidden
        default: throw MonitoringAPIError.serverStatus(httpResponse.statusCode)
        }
    }

    func makeSummaryRequest(baseURLText: String, token: String) throws -> URLRequest {
        let baseURL = try normalizedBaseURL(from: baseURLText)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw MonitoringAPIError.missingToken }

        let url = baseURL.appending(path: "api/v1/summary")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("JARVIS-Dashboard/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    func makeSitesRequest(baseURLText: String, token: String) throws -> URLRequest {
        let baseURL = try normalizedBaseURL(from: baseURLText)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw MonitoringAPIError.missingToken }

        let url = baseURL.appending(path: "api/v1/sites")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("JARVIS-Dashboard/0.2", forHTTPHeaderField: "User-Agent")
        return request
    }

    func makeRegisterSiteRequest(
        baseURLText: String,
        adminToken: String,
        name: String,
        websiteURLText: String,
        platform: MonitoringPlatform
    ) throws -> URLRequest {
        let baseURL = try normalizedBaseURL(from: baseURLText)
        let trimmedToken = adminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw MonitoringAPIError.missingToken }
        guard !trimmedName.isEmpty else { throw MonitoringAPIError.invalidSite }

        let websiteURL = try normalizedWebsiteURL(from: websiteURLText)
        let body: [String: String] = [
            "name": trimmedName,
            "url": websiteURL.absoluteString,
            "platform": platform.rawValue
        ]

        var request = URLRequest(
            url: baseURL.appending(path: "api/v1/sites"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("JARVIS-Dashboard/0.2", forHTTPHeaderField: "User-Agent")
        return request
    }

    func makeUpdateSiteRequest(
        baseURLText: String,
        adminToken: String,
        siteID: String,
        name: String,
        websiteURLText: String,
        platform: MonitoringPlatform
    ) throws -> URLRequest {
        let baseURL = try normalizedBaseURL(from: baseURLText)
        let trimmedToken = adminToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSiteID = siteID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else { throw MonitoringAPIError.missingToken }
        guard !trimmedSiteID.isEmpty, !trimmedName.isEmpty else { throw MonitoringAPIError.invalidSite }

        let websiteURL = try normalizedWebsiteURL(from: websiteURLText)
        let body: [String: String] = [
            "name": trimmedName,
            "url": websiteURL.absoluteString,
            "platform": platform.rawValue
        ]

        var request = URLRequest(
            url: baseURL.appending(path: "api/v1/sites/\(trimmedSiteID)"),
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = "PATCH"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        request.setValue("JARVIS-Dashboard/0.4", forHTTPHeaderField: "User-Agent")
        return request
    }

    func normalizedBaseURL(from text: String) throws -> URL {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmedText),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw MonitoringAPIError.invalidBaseURL
        }

        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" {
            components.path = ""
        }

        guard let url = components.url else { throw MonitoringAPIError.invalidBaseURL }
        return url
    }

    func normalizedWebsiteURL(from text: String) throws -> URL {
        let trimmedText = extractedWebsiteURLText(from: text)
        guard var components = URLComponents(string: trimmedText),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw MonitoringAPIError.invalidSite
        }

        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" { components.path = "" }
        guard let url = components.url else { throw MonitoringAPIError.invalidSite }
        return url
    }

    func extractedWebsiteURLText(from text: String) -> String {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let expression = try? NSRegularExpression(pattern: #"https://[^\s\]\)<>]+"#),
              let match = expression.firstMatch(
                  in: trimmedText,
                  range: NSRange(trimmedText.startIndex..., in: trimmedText)
              ),
              let range = Range(match.range, in: trimmedText) else {
            return trimmedText
        }
        return String(trimmedText[range])
    }

    func parseSummary(data: Data) throws -> MonitoringAPISummary {
        do {
            let envelope = try JSONDecoder().decode(SummaryEnvelope.self, from: data)
            return MonitoringAPISummary(
                sites: envelope.data.sites,
                statuses: MonitoringAPISummary.Statuses(
                    up: envelope.data.statuses.up,
                    down: envelope.data.statuses.down,
                    degraded: envelope.data.statuses.degraded,
                    unknown: envelope.data.statuses.unknown,
                    maintenance: envelope.data.statuses.maintenance
                ),
                openIncidents: envelope.data.openIncidents,
                openFindings: envelope.data.openFindings
            )
        } catch {
            throw MonitoringAPIError.invalidResponse
        }
    }

    func parseSiteRegistration(data: Data) throws -> MonitoringSiteRegistration {
        do {
            let envelope = try JSONDecoder().decode(SiteRegistrationEnvelope.self, from: data)
            guard let platform = MonitoringPlatform(rawValue: envelope.data.platform) else {
                throw MonitoringAPIError.invalidResponse
            }
            return MonitoringSiteRegistration(
                id: envelope.data.id,
                name: envelope.data.name,
                url: envelope.data.url,
                platform: platform,
                ingestToken: envelope.ingestToken
            )
        } catch let error as MonitoringAPIError {
            throw error
        } catch {
            throw MonitoringAPIError.invalidResponse
        }
    }

    func parseSites(data: Data) throws -> [MonitoringSite] {
        do {
            let envelope = try JSONDecoder().decode(SitesEnvelope.self, from: data)
            return try envelope.data.map(mapSite)
        } catch let error as MonitoringAPIError {
            throw error
        } catch {
            throw MonitoringAPIError.invalidResponse
        }
    }

    func parseSite(data: Data) throws -> MonitoringSite {
        do {
            let envelope = try JSONDecoder().decode(SiteEnvelope.self, from: data)
            return try mapSite(envelope.data)
        } catch let error as MonitoringAPIError {
            throw error
        } catch {
            throw MonitoringAPIError.invalidResponse
        }
    }

    private func mapSite(_ site: SitePayload) throws -> MonitoringSite {
        guard let platform = MonitoringPlatform(rawValue: site.platform) else {
            throw MonitoringAPIError.invalidResponse
        }
        let snapshot = site.latestSnapshot.map { payload in
            MonitoringSnapshot(
                checkedAt: Self.date(from: payload.checkedAt),
                phpVersion: payload.phpVersion,
                phpSupported: payload.phpSupported,
                pendingUpdateCount: payload.pendingUpdateCount ?? 0,
                components: (payload.components ?? []).map {
                    MonitoringComponent(
                        ecosystem: $0.ecosystem ?? "unknown",
                        name: $0.name,
                        version: $0.version,
                        latestVersion: $0.latestVersion,
                        updateAvailable: $0.updateAvailable,
                        isDirect: $0.direct,
                        isDevelopment: $0.development
                    )
                },
                notCovered: payload.notCovered ?? [],
                siteHealth: (payload.siteHealth ?? []).map {
                    MonitoringSiteHealthCheck(key: $0.key, label: $0.label, status: $0.status, message: $0.message)
                },
                applicationName: payload.application?.name,
                applicationVersion: payload.application?.version,
                environment: payload.application?.environment
            )
        }

        return MonitoringSite(
            id: site.id,
            name: site.name,
            url: site.url,
            platform: platform,
            status: MonitoringSiteStatus(rawValue: site.status ?? "unknown") ?? .unknown,
            lastCheckAt: Self.date(from: site.lastCheckAt),
            lastStatusCode: site.lastStatusCode,
            lastResponseMilliseconds: site.lastResponseMs,
            lastHeartbeatAt: Self.date(from: site.lastHeartbeatAt),
            lastReportedAt: Self.date(from: site.lastReportedAt),
            sslExpiresAt: Self.date(from: site.sslExpiresAt),
            uptime30DayPercent: site.uptime30dPercent,
            openIncidentsCount: site.openIncidentsCount ?? site.incidents?.filter { $0.endedAt == nil }.count ?? 0,
            openFindingsCount: site.openFindingsCount ?? site.findings?.filter { $0.status == "open" }.count ?? 0,
            latestSnapshot: snapshot,
            incidents: (site.incidents ?? []).map {
                MonitoringIncident(
                    id: $0.id,
                    type: $0.type,
                    startedAt: Self.date(from: $0.startedAt),
                    endedAt: Self.date(from: $0.endedAt),
                    durationSeconds: $0.durationSec
                )
            },
            findings: (site.findings ?? []).map {
                MonitoringFinding(
                    id: $0.id,
                    componentType: $0.componentType ?? "component",
                    slug: $0.slug ?? "unknown",
                    title: $0.title,
                    severity: $0.severity,
                    fixedIn: $0.fixedIn,
                    status: $0.status,
                    referenceURL: $0.referenceUrl
                )
            }
        )
    }

    private static func date(from text: String?) -> Date? {
        guard let text else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}

enum MonitoringAPIError: LocalizedError {
    case invalidBaseURL
    case missingToken
    case invalidResponse
    case unauthorised
    case forbidden
    case adminRequired
    case invalidSite
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter a valid HTTPS API URL."
        case .missingToken:
            "Enter or save an API token first."
        case .invalidResponse:
            "The monitoring API returned an unreadable response."
        case .unauthorised:
            "The API token was not accepted. Check it and try again."
        case .forbidden:
            "The API token does not have read access."
        case .adminRequired:
            "A site-registration token with admin access is required."
        case .invalidSite:
            "Enter a unique project name and a valid HTTPS website URL."
        case let .serverStatus(code):
            "The monitoring API returned HTTP \(code)."
        }
    }
}

private struct SiteRegistrationEnvelope: Decodable {
    struct SitePayload: Decodable {
        let id: String
        let name: String
        let url: String
        let platform: String
    }

    let data: SitePayload
    let ingestToken: String

    enum CodingKeys: String, CodingKey {
        case data
        case ingestToken = "ingest_token"
    }
}

private struct SitesEnvelope: Decodable {
    let data: [SitePayload]
}

private struct SiteEnvelope: Decodable {
    let data: SitePayload
}

private struct SitePayload: Decodable {
    struct SnapshotPayload: Decodable {
        struct ComponentPayload: Decodable {
            let ecosystem: String?
            let name: String
            let version: String
            let latestVersion: String?
            let updateAvailable: Bool?
            let direct: Bool?
            let development: Bool?

            enum CodingKeys: String, CodingKey {
                case ecosystem, name, version, direct, development
                case latestVersion = "latest_version"
                case updateAvailable = "update_available"
            }
        }

        struct HealthPayload: Decodable {
            let key: String
            let label: String
            let status: String
            let message: String?
        }

        struct ApplicationPayload: Decodable {
            let name: String?
            let version: String?
            let environment: String?
        }

        let checkedAt: String?
        let phpVersion: String?
        let phpSupported: Bool?
        let pendingUpdateCount: Int?
        let components: [ComponentPayload]?
        let notCovered: [String]?
        let siteHealth: [HealthPayload]?
        let application: ApplicationPayload?

        enum CodingKeys: String, CodingKey {
            case components, application
            case checkedAt = "checked_at"
            case phpVersion = "php_version"
            case phpSupported = "php_supported"
            case pendingUpdateCount = "pending_update_count"
            case notCovered = "not_covered"
            case siteHealth = "site_health"
        }
    }

    struct IncidentPayload: Decodable {
        let id: String
        let type: String
        let startedAt: String?
        let endedAt: String?
        let durationSec: Int?

        enum CodingKeys: String, CodingKey {
            case id, type
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case durationSec = "duration_sec"
        }
    }

    struct FindingPayload: Decodable {
        let id: String
        let componentType: String?
        let slug: String?
        let title: String
        let severity: String
        let fixedIn: String?
        let status: String
        let referenceUrl: String?

        enum CodingKeys: String, CodingKey {
            case id, slug, title, severity, status
            case componentType = "component_type"
            case fixedIn = "fixed_in"
            case referenceUrl = "reference_url"
        }
    }

    let id: String
    let name: String
    let url: String
    let platform: String
    let status: String?
    let lastCheckAt: String?
    let lastStatusCode: Int?
    let lastResponseMs: Int?
    let lastHeartbeatAt: String?
    let lastReportedAt: String?
    let sslExpiresAt: String?
    let uptime30dPercent: Double?
    let openIncidentsCount: Int?
    let openFindingsCount: Int?
    let latestSnapshot: SnapshotPayload?
    let incidents: [IncidentPayload]?
    let findings: [FindingPayload]?

    enum CodingKeys: String, CodingKey {
        case id, name, url, platform, status, incidents, findings
        case lastCheckAt = "last_check_at"
        case lastStatusCode = "last_status_code"
        case lastResponseMs = "last_response_ms"
        case lastHeartbeatAt = "last_heartbeat_at"
        case lastReportedAt = "last_reported_at"
        case sslExpiresAt = "ssl_expires_at"
        case uptime30dPercent = "uptime_30d_percent"
        case openIncidentsCount = "open_incidents_count"
        case openFindingsCount = "open_findings_count"
        case latestSnapshot = "latest_snapshot"
    }
}

private struct SummaryEnvelope: Decodable {
    struct DataPayload: Decodable {
        struct StatusPayload: Decodable {
            let up: Int
            let down: Int
            let degraded: Int
            let unknown: Int
            let maintenance: Int
        }

        let sites: Int
        let statuses: StatusPayload
        let openIncidents: Int
        let openFindings: Int

        enum CodingKeys: String, CodingKey {
            case sites
            case statuses
            case openIncidents = "open_incidents"
            case openFindings = "open_findings"
        }
    }

    let data: DataPayload
}
