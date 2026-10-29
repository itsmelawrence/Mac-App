import Foundation
import Testing
@testable import JarvisDashboard

struct AlertReliabilityTests {
    @Test func recentAlertIDsForgetOldestFirstAndIgnoreDuplicates() {
        let defaults = UserDefaults(suiteName: "alerts-\(UUID().uuidString)")!
        let memory = RecentAlertIDs(key: "ids", defaults: defaults, limit: 3)
        memory.remember(["a", "b"])
        memory.remember(["b", "c", "d"])
        #expect(memory.load() == ["b", "c", "d"])
    }

    @Test func weatherAlertIDsAreStableWithinADayAndNewTheNextDay() {
        func ids(heat: Double, rain: Int, code: Int, at date: Date) -> [String] {
            let weather = WeatherSnapshot(locationName: "Manila", temperature: 34, apparentTemperature: heat,
                                          weatherCode: code, precipitationProbability: rain)
            return IntelligenceEngine.alerts(weather: [weather], earthquakes: [], articles: [],
                                             earthquakeThreshold: 9, rainThreshold: 60, now: date)
                .map(\.id).sorted()
        }
        let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        let afternoon = morning.addingTimeInterval(5 * 3_600)
        let tomorrow = morning.addingTimeInterval(24 * 3_600)

        // Readings that drift during the day must not create new alert IDs.
        #expect(ids(heat: 43, rain: 70, code: 3, at: morning) == ids(heat: 45, rain: 85, code: 3, at: afternoon))
        // The same storm city alerts again on a new day (previously silenced forever).
        #expect(ids(heat: 30, rain: 90, code: 95, at: morning) != ids(heat: 30, rain: 90, code: 95, at: tomorrow))
    }
}
