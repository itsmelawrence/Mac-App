import Foundation
import Testing
@testable import JarvisDashboard

struct CalendarMathTests {
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ text: String, _ calendar: Calendar) -> Date {
        let parts = text.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    @Test func monthGridIsWholeWeeksFromTheLocalesFirstWeekday() {
        let sunday = calendar(firstWeekday: 1)
        let grid = CalendarMath.monthGrid(containing: date("2026-10-15", sunday), calendar: sunday)
        // October 2026 starts on a Thursday and ends on a Saturday: Sun 27 Sep ... Sat 31 Oct.
        #expect(grid.count == 35)
        #expect(grid.first == date("2026-09-27", sunday))
        #expect(grid.last == date("2026-10-31", sunday))

        let monday = calendar(firstWeekday: 2)
        let mondayGrid = CalendarMath.monthGrid(containing: date("2026-10-15", monday), calendar: monday)
        #expect(mondayGrid.first == date("2026-09-28", monday))
        #expect(mondayGrid.last == date("2026-11-01", monday))
        #expect(mondayGrid.count % 7 == 0)
    }

    @Test func itemsGroupByTheirDayAndUndatedOnesAreLeftOut() {
        let cal = calendar(firstWeekday: 1)
        let morning = cal.date(byAdding: .hour, value: 9, to: date("2026-12-31", cal))!
        let evening = cal.date(byAdding: .hour, value: 21, to: date("2026-12-31", cal))!
        let groups = CalendarMath.byDay([("a", Optional(morning)), ("b", Optional(evening)), ("c", nil)],
                                        date: { $0.1 }, calendar: cal)
        #expect(groups.count == 1)
        #expect(groups[date("2026-12-31", cal)]?.map(\.0) == ["a", "b"])
    }

    @Test func allDayAndMultiDayEventsCoverTheRightDays() {
        let cal = calendar(firstWeekday: 1)
        // An all-day holiday on 30 Nov ends at midnight on 1 Dec, which it doesn't cover.
        let holiday = CalendarMath.days(covering: date("2026-11-30", cal), to: date("2026-12-01", cal), calendar: cal)
        #expect(holiday == [date("2026-11-30", cal)])
        // A trip from the evening of 24 Dec to the morning of 26 Dec covers three days.
        let start = cal.date(byAdding: .hour, value: 18, to: date("2026-12-24", cal))!
        let end = cal.date(byAdding: .hour, value: 10, to: date("2026-12-26", cal))!
        #expect(CalendarMath.days(covering: start, to: end, calendar: cal).count == 3)
    }

    @Test func holidayCalendarsAreRecognisedByName() {
        #expect(CalendarMath.isHolidayCalendar(title: "Holidays in the Philippines", type: .subscription))
        #expect(!CalendarMath.isHolidayCalendar(title: "Work", type: .calDAV))
    }
}
