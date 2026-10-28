import Foundation
import Testing
@testable import JarvisDashboard

struct AlertReliabilityTests {
    @Test func recentAlertIDsForgetOldestFirstAndIgnoreDuplicates() {
        let defaults = UserDefaults(suiteName: "alerts-\(UUID().uuidString)")!
        let memory = RecentAlertIDs(key: "ids", defaults: defaults, limit: 3)
        memory.remember(["a", "b"])
        memory.remember(["b", "c", "d"])
        #expect(memory.load() == ["b", "c", "d"])
    }

    @Test func weatherAlertIDsAreStableWithinADayAndNewTheNextDay() {
        func ids(heat: Double, rain: Int, code: Int, at date: Date) -> [String] {
            let weather = WeatherSnapshot(locationName: "Manila", temperature: 34, apparentTemperature: heat,
                                          weatherCode: code, precipitationProbability: rain)
            return IntelligenceEngine.alerts(weather: [weather], earthquakes: [], articles: [],
                                             earthquakeThreshold: 9, rainThreshold: 60, now: date)
                .map(\.id).sorted()
        }
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let afternoon = morning.addingTimeInterval(5 * 3_600)
        let tomorrow = morning.addingTimeInterval(24 * 3_600)

        // Readings that drift during the day must not create new alert IDs.
        #expect(ids(heat: 43, rain: 70, code: 3, at: morning) == ids(heat: 45, rain: 85, code: 3, at: afternoon))
        // The same storm city alerts again on a new day (previously silenced forever).
        #expect(ids(heat: 30, rain: 90, code: 95, at: morning) != ids(heat: 30, rain: 90, code: 95, at: tomorrow))
    }

    @Test func expiredCertificateCostsMoreThanExpiringSoon() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func score(sslExpiresAt: Date) throws -> MonitoringHealth {
            let site = MonitoringSite(
                id: "site-1", name: "Site", url: "https://example.com", platform: .custom, status: .up,
                lastCheckAt: now, lastHeartbeatAt: now, sslExpiresAt: sslExpiresAt, openFindingsCount: 0,
                latestSnapshot: MonitoringSnapshot(
                    checkedAt: now, phpVersion: "8.4", phpSupported: true, pendingUpdateCount: 0, components: [],
                    notCovered: [], siteHealth: [], applicationName: nil, applicationVersion: nil, environment: nil
                ),
                findings: []
            )
            return MonitoringHealth.evaluate(site: site, connected: true, now: now)
        }
        let expired = try score(sslExpiresAt: now.addingTimeInterval(-86_400))
        let soon = try score(sslExpiresAt: now.addingTimeInterval(7 * 86_400))
        let fine = try score(sslExpiresAt: now.addingTimeInterval(90 * 86_400))
        #expect(expired.deductions.first { $0.id == "ssl" }?.points == 40)
        #expect(soon.deductions.first { $0.id == "ssl" }?.points == 15)
        #expect(fine.deductions.allSatisfy { $0.id != "ssl" })
        let scores = try [expired, soon, fine].map { try #require($0.score) }
        #expect(scores[0] < scores[1] && scores[1] < scores[2])
    }
}
