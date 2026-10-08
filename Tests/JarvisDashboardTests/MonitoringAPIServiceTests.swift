import Foundation
import Testing
@testable import JarvisDashboard

struct MonitoringAPIServiceTests {
    @Test func buildsAuthenticatedSummaryRequest() throws {
        let request = try MonitoringAPIService().makeSummaryRequest(
            baseURLText: " https://example.com/ ",
            token: "  secret-token  "
        )

        #expect(request.url?.absoluteString == "https://example.com/api/v1/summary")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
    }

    @Test func parsesMonitoringSummary() throws {
        let data = Data(#"""
        {
          "data": {
            "sites": 3,
            "statuses": {
              "up": 2,
              "down": 0,
              "degraded": 1,
              "unknown": 0,
              "maintenance": 0
            },
            "open_incidents": 1,
            "open_findings": 4
          }
        }
        """#.utf8)

        let summary = try MonitoringAPIService().parseSummary(data: data)

        #expect(summary.sites == 3)
        #expect(summary.statuses.up == 2)
        #expect(summary.statuses.degraded == 1)
        #expect(summary.openIncidents == 1)
        #expect(summary.openFindings == 4)
    }

    @Test func buildsAdminSiteRegistrationRequest() throws {
        let request = try MonitoringAPIService().makeRegisterSiteRequest(
            baseURLText: "https://api.example.com/",
            adminToken: " admin-token ",
            name: " Client Portal ",
            websiteURLText: "https://client.example.com/",
            platform: .laravel
        )

        #expect(request.url?.absoluteString == "https://api.example.com/api/v1/sites")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer admin-token")

        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(payload["name"] == "Client Portal")
        #expect(payload["url"] == "https://client.example.com")
        #expect(payload["platform"] == "laravel")
    }

    @Test func parsesSiteRegistrationAndOneTimeToken() throws {
        let data = Data(#"""
        {
          "data": {
            "id": "site-123",
            "name": "Client Portal",
            "url": "https://client.example.com",
            "platform": "custom"
          },
          "ingest_token": "3|one-time-reporter-token"
        }
        """#.utf8)

        let registration = try MonitoringAPIService().parseSiteRegistration(data: data)

        #expect(registration.id == "site-123")
        #expect(registration.platform == .custom)
        #expect(registration.ingestToken == "3|one-time-reporter-token")
    }

    @Test func rejectsInsecureBaseURL() {
        #expect(throws: MonitoringAPIError.self) {
            try MonitoringAPIService().normalizedBaseURL(from: "http://example.com")
        }
    }

    @Test func rejectsInsecureWebsiteURL() {
        #expect(throws: MonitoringAPIError.self) {
            try MonitoringAPIService().normalizedWebsiteURL(from: "http://example.com")
        }
    }
}
