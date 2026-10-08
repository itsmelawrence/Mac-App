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

    @Test func rejectsInsecureBaseURL() {
        #expect(throws: MonitoringAPIError.self) {
            try MonitoringAPIService().normalizedBaseURL(from: "http://example.com")
        }
    }
}
