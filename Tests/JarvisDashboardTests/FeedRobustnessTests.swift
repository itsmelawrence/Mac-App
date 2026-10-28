import Foundation
import Testing
@testable import JarvisDashboard

struct FeedRobustnessTests {
    @Test func newsAPIWorldRequestIncludesARequiredFilter() {
        let world = Dictionary(uniqueKeysWithValues: NewsAPIService.queryItems(for: .world).map { ($0.name, $0.value) })
        #expect(world["category"] == "general" && world["language"] == "en")
        let philippines = Dictionary(uniqueKeysWithValues: NewsAPIService.queryItems(for: .philippines).map { ($0.name, $0.value) })
        #expect(philippines["country"] == "ph")
    }

    @Test func newsAPISkipsBadArticlesInsteadOfFailingTheResponse() throws {
        let data = Data(#"""
        {"status": "ok", "articles": [
          {"source": {"name": "Wire"}, "title": "Good story", "url": "https://example.com/a", "publishedAt": "2026-10-28T03:00:00.123Z"},
          {"source": {"name": "Wire"}, "title": null, "url": "https://example.com/b", "publishedAt": null},
          {"source": {"name": null}, "title": "[Removed]", "url": "https://removed.com", "publishedAt": "2026-10-28T03:00:00Z"},
          {"source": null, "title": "No source", "url": "https://example.com/c", "publishedAt": "2026-10-28T03:00:00Z"}
        ]}
        """#.utf8)
        let articles = try NewsAPIService().parse(data: data)
        #expect(articles.map(\.title) == ["Good story", "No source"])
        #expect(articles.first?.publishedAt != nil)  // Fractional seconds parse.
        #expect(articles.last?.sourceName == "NewsAPI")
    }

    @Test func rssTitlesAndLinksInCDATAAreKept() throws {
        let data = Data("""
        <rss><channel><item>
          <title><![CDATA[Typhoon update & advisories]]></title>
          <link><![CDATA[https://example.com/typhoon]]></link>
          <pubDate>Tue, 28 Oct 2026 03:00:00 +0000</pubDate>
        </item></channel></rss>
        """.utf8)
        let articles = try RSSNewsService().parse(data: data, sourceName: "Feed")
        #expect(articles.map(\.title) == ["Typhoon update & advisories"])
        #expect(articles.first?.link.absoluteString == "https://example.com/typhoon")
    }

    @Test func bareAmpersandsOutsideCDATAAreStillRepaired() throws {
        let data = Data("""
        <rss><channel><item>
          <title>Roads & bridges</title>
          <link>https://example.com/roads?a=1&b=2</link>
        </item></channel></rss>
        """.utf8)
        let articles = try RSSNewsService().parse(data: data, sourceName: "Feed")
        #expect(articles.map(\.title) == ["Roads & bridges"])
        #expect(articles.first?.link.absoluteString == "https://example.com/roads?a=1&b=2")
    }

    @Test func unknownMonitoringPlatformKeepsTheSitesList() throws {
        let data = Data(#"""
        {"data": [
          {"id": "s1", "name": "Shop", "url": "https://shop.example.com", "platform": "shopify"},
          {"id": "s2", "name": "Portfolio", "url": "https://portfolio.example.com", "platform": "laravel"}
        ]}
        """#.utf8)
        let sites = try MonitoringAPIService().parseSites(data: data)
        #expect(sites.map(\.platform) == [.custom, .laravel])
    }

    @Test func downOutranksStale() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let site = MonitoringSite(id: "s", name: "Site", url: "https://example.com", platform: .custom, status: .down,
                                  lastCheckAt: now.addingTimeInterval(-72 * 3_600))
        #expect(MonitoringHealth.evaluate(site: site, connected: true, now: now).state == .down)
    }

    @Test func weatherDecodesNullPrecipitation() throws {
        let data = Data(#"""
        {"current": {"temperature_2m": 31.5, "apparent_temperature": 36.0, "weather_code": 3},
         "hourly": {"precipitation_probability": [null]}}
        """#.utf8)
        let snapshot = try OpenMeteoWeatherService.snapshot(from: data, locationName: "Manila")
        #expect(snapshot.precipitationProbability == 0 && snapshot.weatherCode == 3)
    }
}
