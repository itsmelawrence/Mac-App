import Foundation
import Testing
@testable import JarvisDashboard

struct MotivationalQuoteServiceTests {
    @Test func quoteIsStableForTheSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9))!
        let evening = calendar.date(byAdding: .hour, value: 8, to: morning)!

        #expect(
            MotivationalQuoteLibrary.quote(for: morning, calendar: calendar)
                == MotivationalQuoteLibrary.quote(for: evening, calendar: calendar)
        )
    }

    @Test func offsetMovesToAnotherQuote() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let first = MotivationalQuoteLibrary.quote(for: date)
        let next = MotivationalQuoteLibrary.quote(for: date, offset: 1)

        #expect(first.id != next.id)
    }
}
