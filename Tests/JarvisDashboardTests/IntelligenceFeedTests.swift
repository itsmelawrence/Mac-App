import Foundation
import Testing
@testable import JarvisDashboard

@MainActor
struct IntelligenceFeedTests {
    @Test func thresholdsFollowIntelligenceSettingsWithTheirDefaults() throws {
        let defaults = try #require(UserDefaults(suiteName: "IntelligenceFeedTests.\(UUID().uuidString)"))
        let feed = IntelligenceFeed(defaults: defaults)
        #expect(feed.earthquakeThreshold == 5.0)
        #expect(feed.rainThreshold == 70)

        defaults.set(4.5, forKey: "intelligence.earthquakeThreshold")
        defaults.set(0, forKey: "intelligence.rainThreshold")
        #expect(feed.earthquakeThreshold == 4.5)
        // Zero is a real setting, not "unset".
        #expect(feed.rainThreshold == 0)
    }

    @Test func nothingIsReportedBeforeTheFirstFetch() {
        let feed = IntelligenceFeed(defaults: UserDefaults(suiteName: "IntelligenceFeedTests.\(UUID().uuidString)")!)
        #expect(feed.weather(for: "Manila") == nil)
        #expect(!feed.hasFreshWeather)
        #expect(feed.alerts.isEmpty)
        #expect(feed.lastRefreshedAt == nil)
    }
}
