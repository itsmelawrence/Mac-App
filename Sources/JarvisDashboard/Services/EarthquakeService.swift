import Foundation

struct EarthquakeEvent: Identifiable, Sendable {
    let id: String
    let magnitude: Double
    let place: String
    let occurredAt: Date
    let detailURL: URL?

    var severity: String {
        switch magnitude {
        case 0..<3: "Minor"
        case 3..<5: "Light"
        case 5..<6: "Moderate"
        case 6..<7: "Strong"
        default: "Major"
        }
    }
}

protocol EarthquakeProviding: Sendable {
    func recentPhilippineEvents() async throws -> [EarthquakeEvent]
}

struct USGSEarthquakeService: EarthquakeProviding {
    private struct Feed: Decodable {
        let features: [Feature]

        struct Feature: Decodable {
            let id: String
            let properties: Properties
            let geometry: Geometry
        }

        struct Properties: Decodable {
            let mag: Double?
            let place: String?
            let time: Double
            let url: String?
        }

        struct Geometry: Decodable {
            let coordinates: [Double]
        }
    }

    func recentPhilippineEvents() async throws -> [EarthquakeEvent] {
        let url = URL(string: "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/all_day.geojson")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let feed = try JSONDecoder().decode(Feed.self, from: data)
        return feed.features.compactMap { feature in
            guard feature.geometry.coordinates.count >= 2 else { return nil }
            let longitude = feature.geometry.coordinates[0]
            let latitude = feature.geometry.coordinates[1]
            guard (4...22).contains(latitude), (115...130).contains(longitude) else { return nil }

            return EarthquakeEvent(
                id: feature.id,
                magnitude: feature.properties.mag ?? 0,
                place: feature.properties.place ?? "Philippine region",
                occurredAt: Date(timeIntervalSince1970: feature.properties.time / 1_000),
                detailURL: feature.properties.url.flatMap(URL.init(string:))
            )
        }
        .sorted { $0.occurredAt > $1.occurredAt }
    }
}
