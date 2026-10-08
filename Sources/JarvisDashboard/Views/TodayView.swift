import SwiftData
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \ProjectItem.updatedAt, order: .reverse) private var projects: [ProjectItem]
    @Query(sort: \SavedLocation.name) private var savedLocations: [SavedLocation]

    @State private var weather: WeatherSnapshot?
    @State private var earthquakes: [EarthquakeEvent] = []
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var quoteOffset = 0

    private let weatherService = OpenMeteoWeatherService()
    private let earthquakeService = USGSEarthquakeService()

    private var pendingTasks: [TaskItem] { tasks.filter { !$0.isCompleted } }
    private var completedTasks: [TaskItem] { tasks.filter(\.isCompleted) }
    private var blockedTasks: [TaskItem] { pendingTasks.filter(\.isBlocked) }
    private var dueTodayTasks: [TaskItem] {
        pendingTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDateInToday(dueDate)
        }
    }
    private var overdueTasks: [TaskItem] {
        pendingTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate < .now
        }
    }
    private var activeProjects: [ProjectItem] { projects.filter { $0.status == .active } }
    private var significantEarthquakes: [EarthquakeEvent] { earthquakes.filter { $0.magnitude >= 4.5 } }
    private var dailyQuote: MotivationalQuote {
        MotivationalQuoteLibrary.quote(for: .now, offset: quoteOffset)
    }
    private var focusTask: TaskItem? {
        pendingTasks.sorted { lhs, rhs in
            if lhs.isBlocked != rhs.isBlocked { return !lhs.isBlocked }
            if lhs.priorityRawValue != rhs.priorityRawValue { return lhs.priorityRawValue > rhs.priorityRawValue }
            return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }.first
    }
    private var pulseProject: ProjectItem? {
        projects
            .filter { !$0.isArchived && $0.status != .completed }
            .sorted { lhs, rhs in
                if lhs.status == .waitingOnClient, rhs.status != .waitingOnClient { return true }
                if lhs.status != .waitingOnClient, rhs.status == .waitingOnClient { return false }
                if lhs.priority != rhs.priority {
                    return projectPriorityRank(lhs.priority) > projectPriorityRank(rhs.priority)
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first
    }
    private var completionRatio: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTasks.count) / Double(tasks.count)
    }
    private var primaryLocation: SavedLocationValue {
        let location = savedLocations.first(where: \.isPrimary) ?? savedLocations.first
        return location.map {
            SavedLocationValue(name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
        } ?? SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842)
    }

    private var briefing: String {
        BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: pendingTasks.count,
                overdueTaskCount: overdueTasks.count,
                activeProjectCount: activeProjects.count,
                weather: weather,
                significantEarthquakeCount: significantEarthquakes.count
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                briefingCard
                resolveCard
                metricsRow
                operationalWidgets

                HStack(alignment: .top, spacing: 14) {
                    taskSection
                    intelligenceSection
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await refreshIntelligence() }
        .refreshable { await refreshIntelligence() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Command Centre")
                    .font(.largeTitle.bold())
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await refreshIntelligence() }
            } label: {
                Label(isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }
    }

    private var briefingCard: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.cyan)
                .padding(10)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily briefing")
                    .font(.headline)
                Text(briefing)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let refreshError {
                    Text(refreshError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button("Present") { appState.requestBriefing(message: briefing) }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resolveCard: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Daily resolve", systemImage: "quote.opening")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
                    .textCase(.uppercase)
                Text("Perspective for the day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 155, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("“\(dailyQuote.text)”")
                    .font(.system(.title3, design: .serif, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                Text("— \(dailyQuote.author) · \(dailyQuote.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { quoteOffset += 1 }
            } label: {
                Image(systemName: "arrow.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Show another quote")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.cyan.opacity(0.14), .blue.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.cyan.opacity(0.18), lineWidth: 1)
        }
    }

    private var metricsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                metricCards
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
                spacing: 14
            ) {
                metricCards
            }
        }
    }

    @ViewBuilder
    private var metricCards: some View {
        MetricCard(title: "Pending tasks", value: "\(pendingTasks.count)", systemImage: "checklist", tint: .blue)
        MetricCard(title: "Overdue", value: "\(overdueTasks.count)", systemImage: "exclamationmark.circle.fill", tint: overdueTasks.isEmpty ? .green : .red)
        MetricCard(title: "Active projects", value: "\(activeProjects.count)", systemImage: "square.stack.3d.up.fill", tint: .purple)
        MetricCard(title: "Regional alerts", value: "\(significantEarthquakes.count)", systemImage: "waveform.path.ecg", tint: .orange)
    }

    private var operationalWidgets: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                focusWidget
                projectPulseWidget
                momentumWidget
            }
            VStack(spacing: 14) {
                focusWidget
                projectPulseWidget
                momentumWidget
            }
        }
    }

    private var focusWidget: some View {
        TodayWidget(title: "Focus now", systemImage: "scope", tint: .orange) {
            if let focusTask {
                Text(focusTask.title)
                    .font(.headline)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(focusTask.priority.title)
                    if let dueDate = focusTask.dueDate {
                        Text("·")
                        Text(dueDate, format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(dueDate < .now ? .red : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("No open tasks")
                    .font(.headline)
                Text("The runway is clear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var projectPulseWidget: some View {
        TodayWidget(title: "Project pulse", systemImage: "waveform.path", tint: .purple) {
            if let pulseProject {
                Text(pulseProject.name)
                    .font(.headline)
                    .lineLimit(1)
                if pulseProject.status == .waitingOnClient,
                   let days = pulseProject.waitingDays() {
                    Text("Waiting on client · \(days) day\(days == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !pulseProject.nextAction.isEmpty {
                    Text(pulseProject.nextAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(pulseProject.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No active projects")
                    .font(.headline)
                Text("A rare and peaceful condition.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var momentumWidget: some View {
        TodayWidget(title: "Momentum", systemImage: "chart.line.uptrend.xyaxis", tint: .green) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.16), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: completionRatio)
                        .stroke(.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((completionRatio * 100).rounded()))%")
                        .font(.caption.bold())
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(completedTasks.count) completed")
                        .font(.headline)
                    Text("\(dueTodayTasks.count) due today · \(blockedTasks.count) blocked")
                        .font(.caption)
                        .foregroundStyle(blockedTasks.isEmpty ? Color.secondary : Color.orange)
                }
            }
        }
    }

    private var taskSection: some View {
        DashboardSection(title: "Next actions", systemImage: "checkmark.circle") {
            if pendingTasks.isEmpty {
                ContentUnavailableView("No pending tasks", systemImage: "checkmark.seal", description: Text("The queue is clear. Suspiciously efficient."))
                    .frame(height: 180)
            } else {
                VStack(spacing: 0) {
                    ForEach(pendingTasks.prefix(5)) { task in
                        TaskRow(task: task)
                        if task.id != pendingTasks.prefix(5).last?.id { Divider() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var intelligenceSection: some View {
        DashboardSection(title: "Live intelligence", systemImage: "antenna.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: 14) {
                if let weather {
                    HStack(spacing: 12) {
                        Image(systemName: weather.systemImage)
                            .font(.title)
                            .foregroundStyle(.cyan)
                        VStack(alignment: .leading) {
                            Text(weather.locationName).font(.headline)
                            Text("\(Int(weather.temperature.rounded()))° · \(weather.condition)")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Label("Weather awaiting refresh", systemImage: "cloud")
                        .foregroundStyle(.secondary)
                }

                Divider()

                if let event = earthquakes.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Latest regional earthquake").font(.headline)
                        Text("M\(event.magnitude, specifier: "%.1f") · \(event.place)")
                        Text(event.occurredAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("No recent regional reports", systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func refreshIntelligence() async {
        isRefreshing = true
        defer { isRefreshing = false }

        async let weatherRequest = try? weatherService.currentWeather(for: primaryLocation)
        async let earthquakeRequest = try? earthquakeService.recentPhilippineEvents()
        let (newWeather, newEarthquakes) = await (weatherRequest, earthquakeRequest)

        if let newWeather {
            weather = newWeather
        }
        if let newEarthquakes {
            earthquakes = newEarthquakes
        }

        if newWeather != nil, newEarthquakes != nil {
            refreshError = nil
        } else {
            refreshError = "One or more live sources could not be refreshed. Available results remain visible."
        }
    }

    private func projectPriorityRank(_ priority: ProjectPriority) -> Int {
        switch priority {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .urgent: 3
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.system(size: 30, weight: .bold, design: .rounded))
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
        }
        .padding(18)
        .frame(minWidth: 170, maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TodayWidget<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            content
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(minWidth: 230, maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DashboardSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TaskRow: View {
    @Bindable var task: TaskItem

    var body: some View {
        HStack(spacing: 10) {
            Button {
                task.isCompleted.toggle()
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                if let dueDate = task.dueDate {
                    Text(dueDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(dueDate < .now ? .red : .secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 9)
    }
}
