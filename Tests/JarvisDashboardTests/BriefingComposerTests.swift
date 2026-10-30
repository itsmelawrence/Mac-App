import Foundation
import Testing
@testable import JarvisDashboard

struct BriefingComposerTests {
    @Test func prioritisesOverdueTasks() {
        let output = BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: 4,
                overdueTaskCount: 2,
                activeProjectCount: 1,
                weather: nil,
                significantEarthquakeCount: 0
            ),
            date: Date(timeIntervalSince1970: 0),
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(output.contains("2 overdue tasks"))
        #expect(!output.contains("4 pending tasks"))
        #expect(output.contains("1 active project"))
    }

    @Test func producesClearQueueMessage() {
        let output = BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: 0,
                overdueTaskCount: 0,
                activeProjectCount: 0,
                weather: nil,
                significantEarthquakeCount: 0
            )
        )

        #expect(output.contains("task queue is clear"))
    }
}

extension BriefingComposerTests {
    private func briefing(weatherCode: Int? = nil, down: [String] = [], slow: [String] = [], leads: Int = 0) -> String {
        BriefingComposer().compose(BriefingInput(
            pendingTaskCount: 0, overdueTaskCount: 0, activeProjectCount: 0,
            weather: weatherCode.map {
                WeatherSnapshot(locationName: "Manila", temperature: 27.2, apparentTemperature: 30,
                                weatherCode: $0, precipitationProbability: 20)
            },
            significantEarthquakeCount: 0, downSiteNames: down, slowSiteNames: slow, newLeadCount: leads))
    }

    @Test func weatherReadsAsASentence() {
        #expect(briefing(weatherCode: 2).contains("It is 27 degrees and partly cloudy in Manila."))
        #expect(briefing(weatherCode: 61).contains("It is 27 degrees in Manila, with rain."))
        #expect(briefing(weatherCode: 95).contains("It is 27 degrees in Manila, with a thunderstorm."))
        #expect(briefing(weatherCode: 1_000).contains("It is 27 degrees in Manila."))
    }

    @Test func downAndSlowSitesAreNamed() {
        #expect(briefing(down: ["Clinic"]).contains("Clinic is down."))
        #expect(briefing(down: ["A", "B", "C"]).contains("3 websites are down: A, B and C."))
        #expect(briefing(slow: ["My Portfolio Website"]).contains("My Portfolio Website is responding slowly."))
        #expect(!briefing().contains("website"))
    }

    @Test func newLeadsAreCounted() {
        #expect(briefing(leads: 1).contains("A new lead is waiting in Leads."))
        #expect(briefing(leads: 4).contains("4 new leads are waiting in Leads."))
        #expect(!briefing().contains("lead"))
    }
}
