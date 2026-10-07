import Testing
@testable import JarvisDashboard

struct WeatherSnapshotTests {
    @Test func mapsWeatherCodesToReadableConditions() {
        let rain = WeatherSnapshot(
            locationName: "Manila",
            temperature: 28,
            apparentTemperature: 33,
            weatherCode: 63,
            precipitationProbability: 80
        )
        let storm = WeatherSnapshot(
            locationName: "Cebu",
            temperature: 27,
            apparentTemperature: 31,
            weatherCode: 95,
            precipitationProbability: 90
        )

        #expect(rain.condition == "Rain")
        #expect(rain.systemImage == "cloud.rain.fill")
        #expect(storm.condition == "Thunderstorm")
        #expect(storm.systemImage == "cloud.bolt.rain.fill")
    }
}
