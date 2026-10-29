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

    @Test func everyQuoteAppearsOnceBeforeAnyRepeats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        let count = MotivationalQuoteLibrary.quotes.count
        let days = (0..<(count * 3)).map { calendar.date(byAdding: .day, value: $0, to: start)! }
        let ids = days.map { MotivationalQuoteLibrary.quote(for: $0, calendar: calendar).id }

        #expect(Set(MotivationalQuoteLibrary.quotes.map(\.id)).count == count)  // ids are unique
        // Each full pass through the library shows every quote exactly once.
        let passStarts = (0...(ids.count - count)).filter {
            calendar.ordinality(of: .day, in: .era, for: days[$0])! % count == 0
        }
        #expect(passStarts.count >= 2)
        for start in passStarts {
            #expect(Set(ids[start..<(start + count)]).count == count)
        }
        for (today, tomorrow) in zip(ids, ids.dropFirst()) {
            #expect(today != tomorrow)
        }
        #expect(MotivationalQuoteLibrary.order(forPass: 1) != MotivationalQuoteLibrary.order(forPass: 2))
    }
}
