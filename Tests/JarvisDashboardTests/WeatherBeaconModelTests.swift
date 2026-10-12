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

    @Test func animatedArtworkMatchesEachSupportedCondition() {
        #expect(WeatherPointCondition.clear.animatedIconID == "clear")
        #expect(WeatherPointCondition.partlyCloudy.animatedIconID == "partly-cloudy")
        #expect(WeatherPointCondition.cloudy.animatedIconID == "cloudy")
        #expect(WeatherPointCondition.fog.animatedIconID == "fog")
        #expect(WeatherPointCondition.showers.animatedIconID == "light-rain")
        #expect(WeatherPointCondition.rain.animatedIconID == "rain")
        #expect(WeatherPointCondition.heavyRain.animatedIconID == "heavy-rain")
        #expect(WeatherPointCondition.thunderstorm.animatedIconID == "thunderstorm")
        #expect(WeatherPointCondition.unknown.animatedIconID == nil)
    }

    @Test func rainLoopsAndThunderDoubleFlashHaveDistinctFrames() {
        #expect(WeatherIconMotion.fraction(time: 0, period: 1.2) == 0)
        #expect(WeatherIconMotion.fraction(time: 0.6, period: 1.2) == 0.5)
        #expect(WeatherIconMotion.fraction(time: 1.2, period: 1.2) == 0)
        #expect(WeatherIconMotion.thunderFlash(time: 0) == 0)
        #expect(WeatherIconMotion.thunderFlash(time: 3.2 * 0.55) > 0.9)
        #expect(WeatherIconMotion.thunderFlash(time: 3.2 * 0.63) > 0.9)
    }
}
