import Foundation
import Testing
@testable import JarvisDashboard

@Suite struct PhilippineForecastServiceTests {
    @Test func decodesBatchedLocationsAndHourlyValues() throws {
        let item: [String: Any] = [
            "hourly": [
                "time": [1_700_000_000, 1_700_003_600],
                "temperature_2m": [29.5, 30.2],
                "precipitation_probability": [25, 70],
                "precipitation": [0.0, 2.5],
                "wind_speed_10m": [12.0, 18.0],
                "wind_direction_10m": [90.0, 120.0],
                "cloud_cover": [20, 80],
                "relative_humidity_2m": [60, 85],
                "pressure_msl": [1010.0, 1008.0],
                "weather_code": [1, 61]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: Array(repeating: item, count: PhilippineForecastService.locations.count))
        let forecasts = try PhilippineForecastService.decode(data)

        #expect(forecasts.count == PhilippineForecastService.locations.count)
        #expect(forecasts.first?.location.name == "Laoag")
        #expect(forecasts.first?.hours.count == 2)
        #expect(forecasts.first?.hours[1].rainChance == 70)
        #expect(forecasts.first?.hours[1].precipitation == 2.5)
        #expect(forecasts.first?.hour(closestTo: Date(timeIntervalSince1970: 1_700_003_500))?.temperature == 30.2)
    }

    @Test func rejectsIncompleteBatch() throws {
        let data = Data("[]".utf8)
        #expect(throws: URLError.self) { try PhilippineForecastService.decode(data) }
    }

    @Test func decodesSingleSelectedCityAndItsLocalTimeZone() throws {
        let location = SavedLocationValue(name: "London", latitude: 51.5072, longitude: -0.1276)
        let item: [String: Any] = [
            "timezone": "Europe/London",
            "hourly": [
                "time": [1_700_000_000],
                "temperature_2m": [12.4],
                "precipitation_probability": [40],
                "precipitation": [0.2],
                "wind_speed_10m": [16.0],
                "wind_direction_10m": [180.0],
                "cloud_cover": [80],
                "relative_humidity_2m": [75],
                "pressure_msl": [1005.0],
                "weather_code": [61]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: item)
        let result = try PhilippineForecastService.decode(data, locations: [location])
        #expect(result.count == 1)
        #expect(result[0].location.name == "London")
        #expect(result[0].timeZoneIdentifier == "Europe/London")
        #expect(result[0].hours[0].temperature == 12.4)
    }
}
