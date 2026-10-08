import Foundation
import Testing
@testable import JarvisDashboard

struct IntelligenceEngineTests {
    @Test func prioritisesSignificantHazards() {
        let weather = WeatherSnapshot(
            locationName: "Manila",
            temperature: 34,
            apparentTemperature: 43,
            weatherCode: 95,
            precipitationProbability: 90
        )
        let earthquake = EarthquakeEvent(
            id: "event-1",
            magnitude: 6.1,
            place: "Philippine region",
            occurredAt: .now,
            detailURL: nil
        )

        let alerts = IntelligenceEngine.alerts(
            weather: [weather],
            earthquakes: [earthquake],
            articles: [],
            earthquakeThreshold: 5,
            rainThreshold: 70
        )

        #expect(alerts.first?.severity == .critical)
        #expect(alerts.contains(where: { $0.kind == .weather }))
        #expect(alerts.contains(where: { $0.kind == .earthquake }))
    }

    @Test func deduplicatesNewsAndMatchesWatchlist() {
        let first = NewsArticle(
            id: "1",
            title: "AI reshapes local business",
            link: URL(string: "https://example.com/1")!,
            publishedAt: nil,
            sourceName: "Example"
        )
        let duplicate = NewsArticle(
            id: "2",
            title: "AI reshapes local business!",
            link: URL(string: "https://example.com/2")!,
            publishedAt: nil,
            sourceName: "Another"
        )

        #expect(IntelligenceEngine.deduplicated([first, duplicate]).count == 1)
        #expect(IntelligenceEngine.watchlistMatches(articles: [first], keywords: ["AI"]).count == 1)
        let falsePositive = NewsArticle(
            id: "3",
            title: "Failed raid investigation",
            link: URL(string: "https://example.com/3")!,
            publishedAt: nil,
            sourceName: "Example"
        )
        #expect(IntelligenceEngine.watchlistMatches(articles: [falsePositive], keywords: ["AI"]).isEmpty)
    }

    @Test func quietHoursSupportOvernightRanges() {
        #expect(IntelligenceNotificationService.isQuietHour(23, start: 22, end: 7))
        #expect(IntelligenceNotificationService.isQuietHour(6, start: 22, end: 7))
        #expect(!IntelligenceNotificationService.isQuietHour(12, start: 22, end: 7))
    }

    @Test func changeSummaryDescribesDeltas() {
        let summary = IntelligenceChangeSummary(alertDelta: 2, overdueDelta: -1, storyDelta: 0, hasBaseline: true)
        #expect(summary.sentence.contains("+2 priority alerts"))
        #expect(summary.sentence.contains("-1 overdue task"))
    }
}
