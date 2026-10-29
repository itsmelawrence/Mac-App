import SwiftUI

/// The Tasks section's calendar: a month grid of tasks by due date, with events and holidays from the
/// Mac's calendars, and a panel for the selected day.
struct TaskCalendarView: View {
    let tasks: [TaskItem]
    let projectName: (TaskItem) -> String?
    let onEdit: (TaskItem) -> Void
    let onNewTask: (Date) -> Void

    @ObservedObject private var macCalendar = MacCalendarService.shared
    @State private var month = Date.now
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var events: [Date: [CalendarEntry]] = [:]

    private let calendar = Calendar.current
    private var days: [Date] { CalendarMath.monthGrid(containing: month, calendar: calendar) }
    private var tasksByDay: [Date: [TaskItem]] {
        CalendarMath.byDay(TaskQueueEngine.sorted(tasks), date: \.dueDate, calendar: calendar)
    }
    private var unscheduled: Int { tasks.count { $0.dueDate == nil && !$0.isCompleted } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            accessBanner
            HStack(alignment: .top, spacing: 16) {
                monthGrid.frame(maxWidth: .infinity)
                DayPanel(day: selectedDay, tasks: tasksByDay[selectedDay] ?? [], events: events[selectedDay] ?? [],
                         projectName: projectName, onEdit: onEdit, onNewTask: { onNewTask(selectedDay) })
                    .frame(width: 310)
            }
        }
        .task(id: "\(month.timeIntervalSince1970)|\(macCalendar.revision)|\(macCalendar.access == .granted)") { loadEvents() }
        .onAppear { macCalendar.refreshAccess() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
            Spacer()
            if unscheduled > 0 {
                Label("\(unscheduled) without a deadline", systemImage: "calendar.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Tasks with no due date appear in the list view only")
            }
            if macCalendar.access == .granted {
                calendarsMenu
            }
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous month")
            Button("Today") {
                month = .now
                selectedDay = calendar.startOfDay(for: .now)
            }
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .help("Next month")
        }
    }

    private var calendarsMenu: some View {
        Menu {
            let groups = Dictionary(grouping: macCalendar.calendars, by: \.sourceTitle)
            ForEach(groups.keys.sorted(), id: \.self) { source in
                Section(source) {
                    ForEach(groups[source] ?? []) { item in
                        Toggle(item.title, isOn: Binding(
                            get: { !macCalendar.hiddenIDs.contains(item.id) },
                            set: { _ in macCalendar.toggle(item.id) }))
                    }
                }
            }
        } label: {
            Label("Calendars", systemImage: "calendar")
        }
        .fixedSize()
        .help("Choose which Mac calendars show here")
    }

    @ViewBuilder
    private var accessBanner: some View {
        switch macCalendar.access {
        case .granted:
            EmptyView()
        case .notDetermined:
            banner(text: "Show your Mac calendars here, including holidays. JARVIS only reads them.",
                   button: "Connect Calendar") { Task { await macCalendar.requestAccess() } }
        case .denied:
            banner(text: "JARVIS doesn't have access to your calendars. Allow it in System Settings › Privacy & Security › Calendars.",
                   button: "Open System Settings") { macCalendar.openPrivacySettings() }
        }
    }

    private func banner(text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus").foregroundStyle(.cyan)
            Text(text).font(.callout)
            Spacer()
            Button(button, action: action).buttonStyle(.borderedProminent).tint(.cyan)
        }
        .padding(14)
        .background(Color.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Month grid

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let symbols = calendar.shortWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(order, id: \.self) { index in
                    Text(symbols[index].uppercased())
                        .font(.caption2.weight(.bold)).tracking(0.8)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(days, id: \.self) { day in
                    DayCell(day: day,
                            inMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                            isSelected: day == selectedDay,
                            tasks: tasksByDay[day] ?? [],
                            events: events[day] ?? [])
                        .onTapGesture(count: 2) { onNewTask(day) }
                        .onTapGesture { selectedDay = day }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))
        )
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month) ?? month
        if !calendar.isDate(selectedDay, equalTo: month, toGranularity: .month),
           let first = calendar.dateInterval(of: .month, for: month)?.start {
            selectedDay = calendar.isDate(.now, equalTo: month, toGranularity: .month) ? calendar.startOfDay(for: .now) : first
        }
    }

    private func loadEvents() {
        guard let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        var grouped: [Date: [CalendarEntry]] = [:]
        for entry in macCalendar.events(in: DateInterval(start: first, end: end)) {
            for day in CalendarMath.days(covering: entry.start, to: entry.end, calendar: calendar) {
                grouped[day, default: []].append(entry)
            }
        }
        for key in grouped.keys {
            grouped[key]?.sort { ($0.isHoliday ? 0 : $0.isAllDay ? 1 : 2, $0.start) < ($1.isHoliday ? 0 : $1.isAllDay ? 1 : 2, $1.start) }
        }
        events = grouped
    }
}

private struct DayCell: View {
    let day: Date
    let inMonth: Bool
    let isSelected: Bool
    let tasks: [TaskItem]
    let events: [CalendarEntry]
    @State private var isHovering = false

    private var calendar: Calendar { .current }
    private var isToday: Bool { calendar.isDateInToday(day) }
    private var holidays: [CalendarEntry] { events.filter(\.isHoliday) }
    private var others: [CalendarEntry] { events.filter { !$0.isHoliday } }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.callout.weight(isToday ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(isToday ? Color.black : (inMonth ? Color.primary : Color.secondary))
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Circle().fill(isToday ? Color.cyan : Color.clear))
                if let holiday = holidays.first {
                    Text(holiday.title)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(1)
                }
            }
            let lines = lineItems
            ForEach(lines.prefix(3), id: \.id) { line in
                HStack(spacing: 4) {
                    Circle().fill(line.color).frame(width: 6, height: 6)
                    Text(line.title)
                        .font(.system(size: 10.5))
                        .strikethrough(line.done)
                        .foregroundStyle(line.done ? Color.secondary : Color.primary)
                        .lineLimit(1)
                }
            }
            if lines.count > 3 {
                Text("+\(lines.count - 3) more").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.cyan.opacity(0.8) : Color.white.opacity(isHovering ? 0.14 : 0.0), lineWidth: isSelected ? 1.5 : 1)
        )
        .opacity(inMonth ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .help("Click to see this day; double-click to add a task")
    }

    private var background: Color {
        let weekend = calendar.isDateInWeekend(day)
        return Color.white.opacity(weekend ? 0.045 : 0.025)
    }

    private struct Line { let id: String; let title: String; let color: Color; let done: Bool }

    private var lineItems: [Line] {
        let taskLines = tasks.map { task in
            Line(id: task.id.uuidString, title: task.title,
                 color: task.isCompleted ? .green : (TaskQueueEngine.matches(task, scope: .overdue) ? .red : priorityTint(task.priority)),
                 done: task.isCompleted)
        }
        let eventLines = others.map { Line(id: $0.id, title: $0.title, color: $0.color, done: false) }
        return taskLines + eventLines
    }
}

private struct DayPanel: View {
    let day: Date
    let tasks: [TaskItem]
    let events: [CalendarEntry]
    let projectName: (TaskItem) -> String?
    let onEdit: (TaskItem) -> Void
    let onNewTask: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.wide))).font(.caption.weight(.semibold)).foregroundStyle(.cyan)
                Text(day.formatted(.dateTime.day().month(.wide).year())).font(.title3.weight(.semibold))
            }
            ForEach(events.filter(\.isHoliday)) { holiday in
                Label(holiday.title, systemImage: "flag.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(.red.opacity(0.9))
            }

            section("Tasks") {
                if tasks.isEmpty {
                    Text("No tasks due").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(tasks) { task in DayTaskRow(task: task, projectName: projectName(task)) { onEdit(task) } }
                }
            }

            let meetings = events.filter { !$0.isHoliday }
            if !meetings.isEmpty {
                section("Calendar") {
                    ForEach(meetings) { event in
                        HStack(alignment: .top, spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 3, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.callout.weight(.medium)).lineLimit(2)
                                Text(timeText(event) + " · " + event.calendarTitle)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Button(action: onNewTask) {
                Label("Add task for this day", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.cyan.opacity(0.25)))
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
            content()
        }
    }

    private func timeText(_ event: CalendarEntry) -> String {
        if event.isAllDay { return "All day" }
        return "\(event.start.formatted(date: .omitted, time: .shortened))–\(event.end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct DayTaskRow: View {
    @Bindable var task: TaskItem
    let projectName: String?
    let onEdit: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { TaskStore.setCompleted(task, !task.isCompleted) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Color.green : priorityTint(task.priority))
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Reopen" : "Mark complete")
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.callout.weight(.semibold)).strikethrough(task.isCompleted).lineLimit(2)
                Text([projectName ?? "Inbox", task.priority.title,
                      task.dueDate.map { $0.formatted(date: .omitted, time: .shortened) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.white.opacity(isHovering ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { isHovering = $0 }
        .help("Click to edit")
    }
}

private func priorityTint(_ priority: TaskPriority) -> Color {
    switch priority {
    case .low: .secondary
    case .normal: .cyan
    case .high: .orange
    case .critical: .red
    }
}
