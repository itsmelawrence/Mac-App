import Foundation

struct WeatherSnapshot: Sendable {
    let locationName: String
    let temperature: Double
    let apparentTemperature: Double
    let weatherCode: Int
    let precipitationProbability: Int

    var condition: String {
        switch weatherCode {
        case 0: "Clear"
        case 1, 2, 3: "Partly cloudy"
        case 45, 48: "Foggy"
        case 51...67: "Rain"
        case 71...77: "Snow"
        case 80...82: "Rain showers"
        case 85, 86: "Snow showers"
        case 95...99: "Thunderstorm"
        default: "Conditions unavailable"
        }
    }

    var systemImage: String {
        switch weatherCode {
        case 0: "sun.max.fill"
        case 1, 2, 3: "cloud.sun.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...67, 80...82: "cloud.rain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

protocol WeatherProviding: Sendable {
    func currentWeather(for location: SavedLocationValue) async throws -> WeatherSnapshot
}

struct SavedLocationValue: Identifiable, Hashable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double

    var id: String { "\(name)-\(latitude)-\(longitude)" }
}

struct OpenMeteoWeatherService: WeatherProviding {
    private struct Response: Decodable {
        let current: Current
        let hourly: Hourly

        struct Current: Decodable {
            let temperature2m: Double
            let apparentTemperature: Double
            let weatherCode: Int

            enum CodingKeys: String, CodingKey {
                case temperature2m = "temperature_2m"
                case apparentTemperature = "apparent_temperature"
                case weatherCode = "weather_code"
            }
        }

        struct Hourly: Decodable {
            let precipitationProbability: [Int]

            enum CodingKeys: String, CodingKey {
                case precipitationProbability = "precipitation_probability"
            }
        }
    }

    func currentWeather(for location: SavedLocationValue) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(name: "hourly", value: "precipitation_probability"),
            URLQueryItem(name: "forecast_hours", value: "1"),
            URLQueryItem(name: "timezone", value: "Asia/Manila")
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let payload = try decoder.decode(Response.self, from: data)

        return WeatherSnapshot(
            locationName: location.name,
            temperature: payload.current.temperature2m,
            apparentTemperature: payload.current.apparentTemperature,
            weatherCode: payload.current.weatherCode,
            precipitationProbability: payload.hourly.precipitationProbability.first ?? 0
        )
    }
}
