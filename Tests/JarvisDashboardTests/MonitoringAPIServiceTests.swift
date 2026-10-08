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

    @Test func buildsAuthenticatedSitesRequest() throws {
        let request = try MonitoringAPIService().makeSitesRequest(
            baseURLText: "https://api.example.com/",
            token: " read-token "
        )

        #expect(request.url?.absoluteString == "https://api.example.com/api/v1/sites")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer read-token")
    }

    @Test func buildsAdminSiteUpdateRequest() throws {
        let request = try MonitoringAPIService().makeUpdateSiteRequest(
            baseURLText: "https://api.example.com/",
            adminToken: " admin-token ",
            siteID: " site-123 ",
            name: " Skeema Digital Co. ",
            websiteURLText: "[https://skeemadigitalco.com/](https://skeemadigitalco.com/)",
            platform: .wordpress
        )

        #expect(request.url?.absoluteString == "https://api.example.com/api/v1/sites/site-123")
        #expect(request.httpMethod == "PATCH")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer admin-token")

        let body = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(payload["name"] == "Skeema Digital Co.")
        #expect(payload["url"] == "https://skeemadigitalco.com")
        #expect(payload["platform"] == "wordpress")
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

    @Test func parsesExistingSites() throws {
        let data = Data(#"""
        {
          "data": [
            {
              "id": "site-123",
              "name": "Portfolio",
              "url": "https://portfolio.example.com",
              "platform": "laravel"
            }
          ]
        }
        """#.utf8)

        let sites = try MonitoringAPIService().parseSites(data: data)

        #expect(sites == [
            MonitoringSite(
                id: "site-123",
                name: "Portfolio",
                url: "https://portfolio.example.com",
                platform: .laravel
            )
        ])
    }

    @Test func parsesDetailedMonitoringSite() throws {
        let data = Data(#"""
        {
          "data": {
            "id": "site-123",
            "name": "Portfolio",
            "url": "https://portfolio.example.com",
            "platform": "laravel",
            "status": "up",
            "last_check_at": "2026-10-08T10:00:00.000000Z",
            "last_status_code": 200,
            "last_response_ms": 341,
            "last_heartbeat_at": "2026-10-08T10:04:00.000000Z",
            "uptime_30d_percent": 99.98,
            "open_incidents_count": 0,
            "open_findings_count": 1,
            "latest_snapshot": {
              "checked_at": "2026-10-08T10:04:00.000000Z",
              "php_version": "8.4.0",
              "php_supported": true,
              "pending_update_count": 1,
              "components": [{
                "ecosystem": "composer",
                "name": "laravel/framework",
                "version": "12.0.0",
                "latest_version": "12.1.0",
                "update_available": true,
                "direct": true,
                "development": false
              }],
              "not_covered": ["dependency_latest_versions"],
              "site_health": [{"key":"database","label":"Database","status":"pass","message":null}],
              "application": {"name":"portfolio","version":"abc123","environment":"production"}
            },
            "incidents": [],
            "findings": [{
              "id":"finding-1",
              "component_type":"package",
              "slug":"vendor/package",
              "title":"Example advisory",
              "severity":"high",
              "fixed_in":"2.0.0",
              "status":"open",
              "reference_url":"https://example.com/advisory"
            }]
          }
        }
        """#.utf8)

        let site = try MonitoringAPIService().parseSite(data: data)

        #expect(site.status == .up)
        #expect(site.lastStatusCode == 200)
        #expect(site.lastResponseMilliseconds == 341)
        #expect(site.latestSnapshot?.components.first?.updateAvailable == true)
        #expect(site.findings.first?.severity == "high")
        #expect(site.uptime30DayPercent == 99.98)
    }

    @Test func acceptsMarkdownWebsiteLink() throws {
        let url = try MonitoringAPIService().normalizedWebsiteURL(
            from: "[https://lawrenceeemadeit.laravel.cloud/](https://lawrenceeemadeit.laravel.cloud/)"
        )

        #expect(url.absoluteString == "https://lawrenceeemadeit.laravel.cloud")
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
