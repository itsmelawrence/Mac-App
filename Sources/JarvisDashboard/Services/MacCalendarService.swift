import AppKit
import EventKit
import SwiftUI

/// One event from the Mac's calendars, read-only.
struct CalendarEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let color: Color
    let isHoliday: Bool
}

struct CalendarSource: Identifiable, Equatable {
    let id: String
    let title: String
    let sourceTitle: String
    let color: Color
}

/// Reads the Mac's calendars (EventKit), including subscribed Holidays calendars, for the Tasks calendar.
/// JARVIS never changes them. Which calendars show is remembered in `calendar.hiddenIDs`.
@MainActor
final class MacCalendarService: ObservableObject {
    enum Access: Equatable { case notDetermined, granted, denied }

    static let shared = MacCalendarService()
    static let hiddenKey = "calendar.hiddenIDs"

    @Published private(set) var access: Access = .notDetermined
    @Published private(set) var calendars: [CalendarSource] = []
    @Published private(set) var revision = 0
    @Published var hiddenIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenIDs), forKey: Self.hiddenKey) }
    }

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    init() {
        hiddenIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
        refreshAccess()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: access = .granted
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
        if access == .granted { reload() }
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        refreshAccess()
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func reload() {
        guard access == .granted else { return }
        calendars = store.calendars(for: .event)
            .map { CalendarSource(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? "Other",
                                  color: Color(cgColor: $0.cgColor)) }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
        revision += 1
    }

    func toggle(_ id: String) {
        if hiddenIDs.contains(id) { hiddenIDs.remove(id) } else { hiddenIDs.insert(id) }
        revision += 1
    }

    /// Events overlapping `interval` from the calendars that are switched on.
    func events(in interval: DateInterval) -> [CalendarEntry] {
        guard access == .granted else { return [] }
        let visible = store.calendars(for: .event).filter { !hiddenIDs.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: visible)
        return store.events(matching: predicate).map { event in
            CalendarEntry(
                id: "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)",
                title: event.title ?? "Untitled", start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                calendarID: event.calendar.calendarIdentifier, calendarTitle: event.calendar.title,
                color: Color(cgColor: event.calendar.cgColor),
                isHoliday: CalendarMath.isHolidayCalendar(title: event.calendar.title, type: event.calendar.type))
        }
    }
}

/// Date arithmetic for the month view, kept apart from SwiftUI so it can be tested.
enum CalendarMath {
    /// The days shown for the month containing `date`: whole weeks from the locale's first weekday,
    /// so the grid starts before the 1st and ends after the last day when needed.
    static func monthGrid(containing date: Date, calendar: Calendar = .current) -> [Date] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: month.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: lastDay) else { return [] }
        var days: [Date] = []
        var day = firstWeek.start
        while day < lastWeek.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Items grouped by the start of the day they fall on; items without a date are left out.
    static func byDay<Item>(_ items: [Item], date: (Item) -> Date?, calendar: Calendar = .current) -> [Date: [Item]] {
        var groups: [Date: [Item]] = [:]
        for item in items {
            guard let when = date(item) else { continue }
            groups[calendar.startOfDay(for: when), default: []].append(item)
        }
        return groups
    }

    /// Every day an event covers, so a multi-day or all-day event shows on each of them.
    static func days(covering start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: start)
        // An all-day event ends at midnight of the following day; that day isn't covered.
        let last = end > start ? end.addingTimeInterval(-1) : start
        while day <= last {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// macOS's subscribed holiday calendars are named like "Holidays in the Philippines".
    static func isHolidayCalendar(title: String, type: EKCalendarType) -> Bool {
        title.localizedCaseInsensitiveContains("holiday")
    }
}
