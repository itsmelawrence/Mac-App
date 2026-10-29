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

    @Test func groupsEarthquakesCloseInPlaceAndTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func quake(_ id: String, _ magnitude: Double, hoursAgo: Double, lat: Double?, lon: Double?, place: String) -> EarthquakeEvent {
            EarthquakeEvent(id: id, magnitude: magnitude, place: place, occurredAt: now.addingTimeInterval(-hoursAgo * 3_600),
                            detailURL: nil, latitude: lat, longitude: lon)
        }
        let events = [
            quake("a", 5.4, hoursAgo: 11, lat: 9.40, lon: 126.95, place: "114 km ENE of Barcelona, Philippines"),
            quake("b", 5.8, hoursAgo: 15, lat: 9.38, lon: 126.92, place: "110 km ENE of Barcelona, Philippines"),
            quake("c", 5.4, hoursAgo: 15, lat: 9.39, lon: 126.94, place: "113 km ENE of Barcelona, Philippines"),
            quake("d", 5.1, hoursAgo: 2, lat: 16.40, lon: 120.60, place: "10 km N of Baguio, Philippines"),
            quake("e", 5.0, hoursAgo: 80, lat: 9.40, lon: 126.95, place: "112 km ENE of Barcelona, Philippines")
        ]

        let clusters = IntelligenceEngine.clusters(events)

        #expect(clusters.map(\.events.count) == [3, 1, 1])
        #expect(clusters[0].strongest.id == "b")
        #expect(clusters[0].area == "Barcelona, Philippines")
        #expect(clusters[0].latest == events[0].occurredAt)

        // Without coordinates, the place USGS measures from decides.
        let unplaced = events.map { quake($0.id, $0.magnitude, hoursAgo: now.timeIntervalSince($0.occurredAt) / 3_600, lat: nil, lon: nil, place: $0.place) }
        #expect(IntelligenceEngine.clusters(unplaced).map(\.events.count) == [3, 1, 1])
    }
}
