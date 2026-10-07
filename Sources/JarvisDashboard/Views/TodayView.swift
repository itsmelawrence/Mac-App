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

    private let weatherService = OpenMeteoWeatherService()
    private let earthquakeService = USGSEarthquakeService()

    private var pendingTasks: [TaskItem] { tasks.filter { !$0.isCompleted } }
    private var overdueTasks: [TaskItem] {
        pendingTasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate < .now
        }
    }
    private var activeProjects: [ProjectItem] { projects.filter { $0.status == .active } }
    private var significantEarthquakes: [EarthquakeEvent] { earthquakes.filter { $0.magnitude >= 4.5 } }
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

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    MetricCard(title: "Pending tasks", value: "\(pendingTasks.count)", systemImage: "checklist", tint: .blue)
                    MetricCard(title: "Overdue", value: "\(overdueTasks.count)", systemImage: "exclamationmark.circle.fill", tint: overdueTasks.isEmpty ? .green : .red)
                    MetricCard(title: "Active projects", value: "\(activeProjects.count)", systemImage: "square.stack.3d.up.fill", tint: .purple)
                    MetricCard(title: "Regional alerts", value: "\(significantEarthquakes.count)", systemImage: "waveform.path.ecg", tint: .orange)
                }

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
