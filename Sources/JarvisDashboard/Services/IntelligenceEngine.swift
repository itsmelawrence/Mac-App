import Foundation

enum IntelligenceSeverity: Int, Comparable, Sendable {
    case information = 0
    case advisory = 1
    case warning = 2
    case critical = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .information: "Information"
        case .advisory: "Advisory"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

struct IntelligenceAlert: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case weather
        case earthquake
        case news
        case operations
    }

    let id: String
    let title: String
    let detail: String
    let severity: IntelligenceSeverity
    let kind: Kind
    let occurredAt: Date
    let source: String
    let destination: URL?
}

struct IntelligenceChangeSummary: Equatable, Sendable {
    let alertDelta: Int
    let overdueDelta: Int
    let storyDelta: Int
    let hasBaseline: Bool

    var sentence: String {
        guard hasBaseline else {
            return "Baseline recorded. Future refreshes will highlight what changed."
        }

        let changes = [
            Self.phrase(alertDelta, singular: "priority alert", plural: "priority alerts"),
            Self.phrase(overdueDelta, singular: "overdue task", plural: "overdue tasks"),
            Self.phrase(storyDelta, singular: "news story", plural: "news stories")
        ].compactMap { $0 }

        return changes.isEmpty ? "No material count changes since the previous refresh." : changes.joined(separator: " · ")
    }

    private static func phrase(_ value: Int, singular: String, plural: String) -> String? {
        guard value != 0 else { return nil }
        let noun = abs(value) == 1 ? singular : plural
        return value > 0 ? "+\(value) \(noun)" : "\(value) \(noun)"
    }
}

enum IntelligenceEngine {
    static func alerts(
        weather: [WeatherSnapshot],
        earthquakes: [EarthquakeEvent],
        articles: [NewsArticle],
        earthquakeThreshold: Double,
        rainThreshold: Int,
        now: Date = .now
    ) -> [IntelligenceAlert] {
        var output: [IntelligenceAlert] = []

        for snapshot in weather {
            if (95...99).contains(snapshot.weatherCode) {
                output.append(
                    IntelligenceAlert(
                        id: "weather-storm-\(snapshot.locationName)",
                        title: "Thunderstorm conditions in \(snapshot.locationName)",
                        detail: "Current conditions report \(snapshot.condition.lowercased()) with a \(snapshot.precipitationProbability)% precipitation probability.",
                        severity: .warning,
                        kind: .weather,
                        occurredAt: now,
                        source: "Open-Meteo",
                        destination: nil
                    )
                )
            } else if snapshot.precipitationProbability >= rainThreshold {
                output.append(
                    IntelligenceAlert(
                        id: "weather-rain-\(snapshot.locationName)-\(snapshot.precipitationProbability)",
                        title: "High rain probability in \(snapshot.locationName)",
                        detail: "Precipitation probability is \(snapshot.precipitationProbability)% for the current forecast hour.",
                        severity: .advisory,
                        kind: .weather,
                        occurredAt: now,
                        source: "Open-Meteo",
                        destination: nil
                    )
                )
            }

            if snapshot.apparentTemperature >= 42 {
                output.append(
                    IntelligenceAlert(
                        id: "weather-heat-\(snapshot.locationName)-\(Int(snapshot.apparentTemperature))",
                        title: "Dangerous apparent heat in \(snapshot.locationName)",
                        detail: "It currently feels like \(Int(snapshot.apparentTemperature.rounded()))°C.",
                        severity: .warning,
                        kind: .weather,
                        occurredAt: now,
                        source: "Open-Meteo",
                        destination: nil
                    )
                )
            }
        }

        output += earthquakes
            .filter { $0.magnitude >= earthquakeThreshold }
            .map { event in
                IntelligenceAlert(
                    id: "earthquake-\(event.id)",
                    title: "M\(event.magnitude.formatted(.number.precision(.fractionLength(1)))) regional earthquake",
                    detail: event.place,
                    severity: event.magnitude >= 6 ? .critical : .warning,
                    kind: .earthquake,
                    occurredAt: event.occurredAt,
                    source: "USGS · confirm with PHIVOLCS",
                    destination: event.detailURL
                )
            }

        let hazardTerms = ["typhoon", "tropical cyclone", "storm signal", "flood", "landslide", "tsunami", "volcanic", "earthquake"]
        output += deduplicated(articles).compactMap { article in
            let title = article.title.lowercased()
            guard let term = hazardTerms.first(where: title.contains) else { return nil }
            return IntelligenceAlert(
                id: "news-\(article.id)",
                title: article.title,
                detail: "Potential \(term) development reported in the news. Verify against the relevant government bulletin.",
                severity: .advisory,
                kind: .news,
                occurredAt: article.publishedAt ?? now,
                source: article.sourceName,
                destination: article.link
            )
        }

        return output.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.occurredAt > $1.occurredAt
        }
    }

    static func deduplicated(_ articles: [NewsArticle]) -> [NewsArticle] {
        var seen = Set<String>()
        return articles.filter { article in
            let key = article.title
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .prefix(12)
                .joined(separator: " ")
            return seen.insert(key.isEmpty ? article.link.absoluteString : key).inserted
        }
    }

    static func watchlistMatches(articles: [NewsArticle], keywords: [String]) -> [NewsArticle] {
        let terms = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return deduplicated(articles).filter { article in
            let searchable = "\(article.title) \(article.sourceName)".lowercased()
            let words = Set(
                searchable
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
            )
            return terms.contains { term in
                term.contains(" ") ? searchable.contains(term) : words.contains(term)
            }
        }
    }
}
