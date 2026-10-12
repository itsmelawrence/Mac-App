import Foundation

struct PhilippineForecastHour: Equatable, Sendable {
    let time: Date
    let temperature: Double?
    let rainChance: Int?
    let precipitation: Double?
    let windSpeed: Double?
    let windDirection: Double?
    let cloudCover: Int?
    let humidity: Int?
    let pressure: Double?
    let weatherCode: Int?
}

struct PhilippineLocationForecast: Identifiable, Sendable {
    let location: SavedLocationValue
    let hours: [PhilippineForecastHour]
    let timeZoneIdentifier: String

    init(location: SavedLocationValue, hours: [PhilippineForecastHour], timeZoneIdentifier: String = "Asia/Manila") {
        self.location = location
        self.hours = hours
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    var id: String { location.id }

    func hour(closestTo date: Date) -> PhilippineForecastHour? {
        hours.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }

    func hasThunderstorm(at index: Int) -> Bool {
        guard hours.indices.contains(index) else { return false }
        let hour = hours[index]
        return WeatherPointCondition(code: hour.weatherCode, precipitation: hour.precipitation).isThunderstorm
    }
}

struct PhilippineForecastService: Sendable {
    // Representative land points, not a continuous raster or official warning grid.
    static let locations: [SavedLocationValue] = [
        .init(name: "Laoag", latitude: 18.1987, longitude: 120.5936),
        .init(name: "Tuguegarao", latitude: 17.6132, longitude: 121.7270),
        .init(name: "Baguio", latitude: 16.4023, longitude: 120.5960),
        .init(name: "Dagupan", latitude: 16.0433, longitude: 120.3333),
        .init(name: "Manila", latitude: 14.5995, longitude: 120.9842),
        .init(name: "Lucena", latitude: 13.9314, longitude: 121.6170),
        .init(name: "Legazpi", latitude: 13.1391, longitude: 123.7438),
        .init(name: "Puerto Princesa", latitude: 9.7392, longitude: 118.7353),
        .init(name: "Calapan", latitude: 13.4117, longitude: 121.1803),
        .init(name: "Iloilo", latitude: 10.7202, longitude: 122.5621),
        .init(name: "Cebu", latitude: 10.3157, longitude: 123.8854),
        .init(name: "Tacloban", latitude: 11.2444, longitude: 125.0039),
        .init(name: "Zamboanga", latitude: 6.9214, longitude: 122.0790),
        .init(name: "Cagayan de Oro", latitude: 8.4542, longitude: 124.6319),
        .init(name: "Davao", latitude: 7.1907, longitude: 125.4553),
        .init(name: "General Santos", latitude: 6.1164, longitude: 125.1716)
    ]

    private struct Response: Decodable {
        let timezone: String?
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [Int]
            let temperature: [Double?]
            let rainChance: [Int?]
            let precipitation: [Double?]
            let windSpeed: [Double?]
            let windDirection: [Double?]
            let cloudCover: [Int?]
            let humidity: [Int?]
            let pressure: [Double?]
            let weatherCode: [Int?]

            enum CodingKeys: String, CodingKey {
                case time
                case temperature = "temperature_2m"
                case rainChance = "precipitation_probability"
                case precipitation
                case windSpeed = "wind_speed_10m"
                case windDirection = "wind_direction_10m"
                case cloudCover = "cloud_cover"
                case humidity = "relative_humidity_2m"
                case pressure = "pressure_msl"
                case weatherCode = "weather_code"
            }
        }
    }

    func forecast() async throws -> [PhilippineLocationForecast] {
        try await forecast(for: Self.locations, timeZone: "Asia/Manila")
    }

    func forecast(for locations: [SavedLocationValue], timeZone: String = "auto") async throws -> [PhilippineLocationForecast] {
        guard !locations.isEmpty else { return [] }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: locations.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: locations.map { String($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m,cloud_cover,relative_humidity_2m,pressure_msl,weather_code"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: timeZone)
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try Self.decode(data, locations: locations)
    }

    static func decode(_ data: Data) throws -> [PhilippineLocationForecast] {
        try decode(data, locations: locations)
    }

    static func decode(_ data: Data, locations: [SavedLocationValue]) throws -> [PhilippineLocationForecast] {
        let responses: [Response]
        if locations.count == 1, let single = try? JSONDecoder().decode(Response.self, from: data) {
            responses = [single]
        } else {
            responses = try JSONDecoder().decode([Response].self, from: data)
        }
        guard responses.count == locations.count else { throw URLError(.cannotParseResponse) }
        return zip(locations, responses).map { location, response in
            let hourly = response.hourly
            let count = hourly.time.count
            let arrays = [hourly.temperature.count, hourly.rainChance.count, hourly.precipitation.count,
                          hourly.windSpeed.count, hourly.windDirection.count, hourly.cloudCover.count,
                          hourly.humidity.count, hourly.pressure.count, hourly.weatherCode.count]
            let validCount = arrays.min().map { min(count, $0) } ?? 0
            let hours = (0..<validCount).map { index in
                PhilippineForecastHour(
                    time: Date(timeIntervalSince1970: TimeInterval(hourly.time[index])),
                    temperature: hourly.temperature[index],
                    rainChance: hourly.rainChance[index],
                    precipitation: hourly.precipitation[index],
                    windSpeed: hourly.windSpeed[index],
                    windDirection: hourly.windDirection[index],
                    cloudCover: hourly.cloudCover[index],
                    humidity: hourly.humidity[index],
                    pressure: hourly.pressure[index],
                    weatherCode: hourly.weatherCode[index]
                )
            }
            return PhilippineLocationForecast(location: location, hours: hours,
                                              timeZoneIdentifier: response.timezone ?? "Asia/Manila")
        }
    }
}
