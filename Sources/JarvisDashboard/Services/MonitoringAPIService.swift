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
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
