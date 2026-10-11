import Testing
@testable import JarvisDashboard

@Suite struct WeatherBeaconModelTests {
    @Test func weatherCodesMapToHonestConditions() {
        #expect(WeatherPointCondition(code: 0, precipitation: 0) == .clear)
        #expect(WeatherPointCondition(code: 3, precipitation: 0) == .cloudy)
        #expect(WeatherPointCondition(code: 51, precipitation: 0.2) == .showers)
        #expect(WeatherPointCondition(code: 61, precipitation: 8) == .heavyRain)
        #expect(WeatherPointCondition(code: 95, precipitation: nil) == .thunderstorm)
        #expect(WeatherPointCondition(code: nil, precipitation: nil) == .unknown)
    }

    @Test func rainBandsRespectBoundariesAndMissingData() {
        #expect(WeatherRainBand(chance: 29, thunderstorm: false) == .low)
        #expect(WeatherRainBand(chance: 30, thunderstorm: false) == .moderate)
        #expect(WeatherRainBand(chance: 60, thunderstorm: false) == .high)
        #expect(WeatherRainBand(chance: 80, thunderstorm: false) == .extreme)
        #expect(WeatherRainBand(chance: 25, thunderstorm: true) == .thunderstorm)
        #expect(WeatherRainBand(chance: nil, thunderstorm: true) == .unavailable)
    }
}
