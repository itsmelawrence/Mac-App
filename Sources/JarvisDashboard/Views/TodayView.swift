import SwiftData
import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \ProjectItem.updatedAt, order: .reverse) private var projects: [ProjectItem]
    @Query(sort: \SavedLocation.name) private var savedLocations: [SavedLocation]

    @AppStorage("monitoring.apiBaseURL") private var monitoringAPIBaseURL = MonitoringAPIService.defaultBaseURL
    @State private var weather: WeatherSnapshot?
    @State private var earthquakes: [EarthquakeEvent] = []
    @State private var monitoringSites: [String: MonitoringSite] = [:]
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var monitoringError: String?
    @State private var quoteOffset = 0
    @State private var showingCommandConsole = false

    private let weatherService = OpenMeteoWeatherService()
    private let earthquakeService = USGSEarthquakeService()
    private let monitoringService = MonitoringAPIService()
    private let monitoringCredentialStore = MonitoringAPICredentialStore()

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
        pendingTasks.filter { ($0.dueDate ?? .distantFuture) < .now }
    }
    private var operationalProjects: [ProjectItem] {
        projects.filter { !$0.isArchived && $0.status != .completed }
    }
    private var waitingProjects: [ProjectItem] { operationalProjects.filter { $0.status == .waitingOnClient } }
    private var significantEarthquakes: [EarthquakeEvent] { earthquakes.filter { $0.magnitude >= 4.5 } }
    private var dailyQuote: MotivationalQuote { MotivationalQuoteLibrary.quote(for: .now, offset: quoteOffset) }

    private var sortedTasks: [TaskItem] {
        pendingTasks.sorted { lhs, rhs in
            if lhs.isBlocked != rhs.isBlocked { return lhs.isBlocked }
            let lhsOverdue = (lhs.dueDate ?? .distantFuture) < .now
            let rhsOverdue = (rhs.dueDate ?? .distantFuture) < .now
            if lhsOverdue != rhsOverdue { return lhsOverdue }
            if lhs.priorityRawValue != rhs.priorityRawValue { return lhs.priorityRawValue > rhs.priorityRawValue }
            return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
    }
    private var sortedProjects: [ProjectItem] {
        operationalProjects.sorted { lhs, rhs in
            let lhsHealth = monitoringHealth(for: lhs)
            let rhsHealth = monitoringHealth(for: rhs)
            if lhsHealth.sortRank != rhsHealth.sortRank { return lhsHealth.sortRank < rhsHealth.sortRank }
            if lhs.priority != rhs.priority { return priorityRank(lhs.priority) > priorityRank(rhs.priority) }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
    private var monitoredProjects: [ProjectItem] { projects.filter(\.hasMonitoringSite) }
    private var unhealthySiteCount: Int { monitoredProjects.filter { monitoringHealth(for: $0).needsAttention }.count }
    private var healthySiteCount: Int { monitoredProjects.filter { monitoringHealth(for: $0).state == .healthy }.count }
    private var attentionCount: Int { overdueTasks.count + blockedTasks.count + waitingProjects.count + unhealthySiteCount }
    private var completionRatio: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(completedTasks.count) / Double(tasks.count)
    }
    private var primaryLocation: SavedLocationValue {
        let location = savedLocations.first(where: \.isPrimary) ?? savedLocations.first
        return location.map { SavedLocationValue(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
            ?? SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842)
    }
    private var briefing: String {
        BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: pendingTasks.count,
                overdueTaskCount: overdueTasks.count,
                activeProjectCount: operationalProjects.count,
                weather: weather,
                significantEarthquakeCount: significantEarthquakes.count
            )
        )
    }
    private var commandContext: JarvisCommandContext {
        JarvisCommandContext(
            briefing: briefing,
            pendingTasks: pendingTasks.count,
            overdueTasks: overdueTasks.count,
            activeProjects: operationalProjects.count,
            monitoredSites: monitoredProjects.count,
            unhealthySites: unhealthySiteCount
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                commandHeader
                statusRail

                HStack(alignment: .top, spacing: 16) {
                    primaryColumn.frame(maxWidth: .infinity)
                    intelligenceColumn.frame(width: 300)
                }

                resolveCard
            }
            .padding(28)
        }
        .background(commandBackground)
        .task { await refreshCommandCentre() }
        .refreshable { await refreshCommandCentre() }
        .sheet(isPresented: $showingCommandConsole) {
            JarvisCommandConsole(context: commandContext) { result in
                if let destination = result.destination { appState.selection = destination }
                if result.shouldSpeak { speechService.speak(result.response) }
            }
        }
    }

    private var commandBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.012, green: 0.028, blue: 0.052), Color(nsColor: .windowBackgroundColor)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var commandHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(Date.now.formatted(date: .complete, time: .omitted))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            attentionBadge
            Button { showingCommandConsole = true } label: {
                Label("Ask JARVIS", systemImage: "waveform.circle.fill")
                    .fontWeight(.semibold).padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .keyboardShortcut("k", modifiers: .command)
            Button { Task { await refreshCommandCentre() } } label: {
                Image(systemName: isRefreshing ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
            .help("Refresh command centre")
        }
    }

    private var attentionBadge: some View {
        HStack(spacing: 7) {
            Circle().fill(attentionCount == 0 ? Color.green : Color.orange).frame(width: 7, height: 7)
            Text(attentionCount == 0 ? "Systems nominal" : "\(attentionCount) require attention")
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(attentionCount == 0 ? Color.secondary : Color.orange)
    }

    private var statusRail: some View {
        HStack(spacing: 0) {
            CommandMetric(title: "Open tasks", value: "\(pendingTasks.count)", tint: .primary)
            CommandDivider()
            CommandMetric(title: "Overdue", value: "\(overdueTasks.count)", tint: overdueTasks.isEmpty ? .secondary : .red)
            CommandDivider()
            CommandMetric(title: "Active operations", value: "\(operationalProjects.count)", tint: .primary)
            CommandDivider()
            CommandMetric(title: "Sites healthy", value: "\(healthySiteCount)/\(monitoredProjects.count)", tint: unhealthySiteCount == 0 ? .green : .orange)
            CommandDivider()
            CommandMetric(title: "Regional alerts", value: "\(significantEarthquakes.count)", tint: significantEarthquakes.isEmpty ? .secondary : .orange)
        }
        .padding(.vertical, 14)
        .commandSurface(cornerRadius: 14)
    }

    private var primaryColumn: some View {
        VStack(spacing: 16) {
            briefingCard
            activeOperationsCard
            nextActionsCard
        }
    }

    private var intelligenceColumn: some View {
        VStack(spacing: 16) {
            weatherCard
            intelligenceCard
            systemStatusCard
            momentumCard
        }
    }

    private var briefingCard: some View {
        CommandPanel(title: "Today's briefing", systemImage: "sparkles") {
            Text(briefing)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let refreshError {
                Label(refreshError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Present briefing", systemImage: "speaker.wave.2.fill") {
                    appState.requestBriefing(message: briefing)
                    speechService.speak(briefing)
                }
                .buttonStyle(.bordered)
                Spacer()
                Text("Live operational summary").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var activeOperationsCard: some View {
        CommandPanel(title: "Active operations", systemImage: "square.stack.3d.up.fill") {
            if sortedProjects.isEmpty {
                CommandEmptyState(title: "No active operations", detail: "The board is clear. Almost suspiciously so.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedProjects.prefix(4).enumerated()), id: \.element.id) { index, project in
                        OperationRow(
                            project: project,
                            health: monitoringHealth(for: project),
                            taskCount: pendingTasks.filter { $0.projectID == project.id }.count
                        ) { appState.selection = .projects }
                        if index < min(sortedProjects.count, 4) - 1 { Divider().opacity(0.45) }
                    }
                }
                if sortedProjects.count > 4 {
                    Button("View all \(sortedProjects.count) operations") { appState.selection = .projects }
                        .buttonStyle(.plain).foregroundStyle(.cyan)
                }
            }
        }
    }

    private var nextActionsCard: some View {
        CommandPanel(title: "Next actions", systemImage: "checkmark.circle") {
            if sortedTasks.isEmpty {
                CommandEmptyState(title: "No pending tasks", detail: "The queue is clear.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedTasks.prefix(5).enumerated()), id: \.element.id) { index, task in
                        TodayTaskRow(task: task)
                        if index < min(sortedTasks.count, 5) - 1 { Divider().opacity(0.45) }
                    }
                }
                Button("Open task queue") { appState.selection = .tasks }
                    .buttonStyle(.plain).foregroundStyle(.cyan)
            }
        }
    }

    private var weatherCard: some View {
        CommandPanel(title: "Weather", systemImage: "cloud.sun.fill") {
            if let weather {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: weather.systemImage).font(.system(size: 30)).foregroundStyle(.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(weather.temperature.rounded()))°").font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(weather.condition).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(weather.locationName).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            } else {
                CommandEmptyState(title: "Weather unavailable", detail: "Awaiting the next live refresh.")
            }
        }
    }

    private var intelligenceCard: some View {
        CommandPanel(title: "Intelligence", systemImage: "antenna.radiowaves.left.and.right") {
            if let event = earthquakes.first {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Latest regional earthquake").font(.caption).foregroundStyle(.secondary)
                    Text("M\(event.magnitude, specifier: "%.1f") · \(event.place)")
                        .font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(event.occurredAt, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                Label("No recent regional signals", systemImage: "checkmark.shield.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
            Button("Open intelligence") { appState.selection = .intelligence }
                .buttonStyle(.plain).foregroundStyle(.cyan)
        }
    }

    private var systemStatusCard: some View {
        CommandPanel(title: "System status", systemImage: "server.rack") {
            statusLine(label: "Monitoring API", value: monitoringError == nil ? "Online" : "Attention", colour: monitoringError == nil ? .green : .orange)
            statusLine(label: "Monitored sites", value: "\(monitoredProjects.count)", colour: .secondary)
            statusLine(label: "Healthy", value: "\(healthySiteCount)", colour: .green)
            if unhealthySiteCount > 0 { statusLine(label: "Attention", value: "\(unhealthySiteCount)", colour: .orange) }
            if let monitoringError {
                Text(monitoringError).font(.caption2).foregroundStyle(.orange).lineLimit(3)
            }
        }
    }

    private var momentumCard: some View {
        CommandPanel(title: "Momentum", systemImage: "chart.line.uptrend.xyaxis") {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.16), lineWidth: 5)
                    Circle().trim(from: 0, to: completionRatio)
                        .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int((completionRatio * 100).rounded()))%").font(.caption.bold())
                }
                .frame(width: 50, height: 50)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(completedTasks.count) completed").font(.subheadline.weight(.semibold))
                    Text("\(dueTodayTasks.count) due today")
                    Text("\(blockedTasks.count) blocked").foregroundStyle(blockedTasks.isEmpty ? Color.secondary : Color.orange)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var resolveCard: some View {
        HStack(spacing: 16) {
            Image(systemName: "quote.opening").foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text("“\(dailyQuote.text)”").font(.system(.body, design: .serif, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text("— \(dailyQuote.author) · \(dailyQuote.source)").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { quoteOffset += 1 }
            } label: { Image(systemName: "arrow.right") }
                .buttonStyle(.plain).help("Show another quote")
        }
        .padding(18)
        .commandSurface(cornerRadius: 14)
    }

    private func statusLine(label: String, value: String, colour: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(colour)
        }
        .font(.caption)
    }

    @MainActor
    private func refreshCommandCentre() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let weatherRequest = try? weatherService.currentWeather(for: primaryLocation)
        async let earthquakeRequest = try? earthquakeService.recentPhilippineEvents()
        async let monitoringRequest: [MonitoringSite]? = refreshMonitoringSites()
        let (newWeather, newEarthquakes, newMonitoringSites) = await (weatherRequest, earthquakeRequest, monitoringRequest)

        if let newWeather { weather = newWeather }
        if let newEarthquakes { earthquakes = newEarthquakes }
        if let newMonitoringSites {
            monitoringSites = Dictionary(uniqueKeysWithValues: newMonitoringSites.map { ($0.id, $0) })
            monitoringError = nil
        }
        refreshError = newWeather == nil || newEarthquakes == nil
            ? "One or more intelligence sources could not be refreshed; available results remain visible."
            : nil
    }

    private func refreshMonitoringSites() async -> [MonitoringSite]? {
        guard let token = monitoringCredentialStore.read() else {
            await MainActor.run { monitoringError = "Add a monitoring read token in Settings." }
            return nil
        }
        do {
            let summaries = try await monitoringService.sites(baseURLText: monitoringAPIBaseURL, readToken: token)
            return try await withThrowingTaskGroup(of: MonitoringSite.self) { group in
                for summary in summaries {
                    group.addTask {
                        try await monitoringService.site(baseURLText: monitoringAPIBaseURL, readToken: token, siteID: summary.id)
                    }
                }
                var details: [MonitoringSite] = []
                for try await site in group { details.append(site) }
                return details
            }
        } catch {
            await MainActor.run { monitoringError = error.localizedDescription }
            return nil
        }
    }

    private func monitoringSite(for project: ProjectItem) -> MonitoringSite? {
        guard !project.monitoringSiteID.isEmpty else { return nil }
        return monitoringSites[project.monitoringSiteID]
    }
    private func monitoringHealth(for project: ProjectItem) -> MonitoringHealth {
        MonitoringHealth.evaluate(site: monitoringSite(for: project), connected: project.hasMonitoringSite)
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning, Lawrence"
        case 12..<18: "Good afternoon, Lawrence"
        default: "Good evening, Lawrence"
        }
    }
    private func priorityRank(_ priority: ProjectPriority) -> Int {
        switch priority { case .low: 0; case .medium: 1; case .high: 2; case .urgent: 3 }
    }
}

private struct CommandMetric: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

private struct CommandDivider: View {
    var body: some View { Rectangle().fill(.secondary.opacity(0.14)).frame(width: 1, height: 34) }
}

private struct CommandPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(.cyan)
                Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.7).foregroundStyle(.secondary)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .commandSurface(cornerRadius: 14)
    }
}

private struct OperationRow: View {
    let project: ProjectItem
    let health: MonitoringHealth
    let taskCount: Int
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle().fill(statusColour).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(detailText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(statusText).font(.caption.weight(.semibold)).foregroundStyle(statusColour)
                    Text("\(taskCount) open task\(taskCount == 1 ? "" : "s")").font(.caption2).foregroundStyle(.tertiary)
                }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle()).padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
    private var statusText: String {
        if project.status == .waitingOnClient { return "Waiting on client" }
        if project.status == .onHold { return "Blocked" }
        if project.hasMonitoringSite { return health.label }
        return project.status.title
    }
    private var statusColour: Color {
        if project.status == .waitingOnClient || project.status == .onHold { return .orange }
        return project.hasMonitoringSite ? health.colour : .secondary
    }
    private var detailText: String {
        if !project.nextAction.isEmpty { return project.nextAction }
        if project.mode == .fixed { return "\(Int((project.progress * 100).rounded()))% complete" }
        return project.client.isEmpty ? project.mode.title : project.client
    }
}

private struct CommandEmptyState: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }
}

private struct JarvisCommandConsole: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var commandFocused: Bool
    @State private var command = ""
    @State private var response = "Awaiting your command, Sir."
    let context: JarvisCommandContext
    let onResult: (JarvisCommandResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("JARVIS Command Console", systemImage: "waveform.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.cyan)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                TextField("Ask for a briefing or open a system…", text: $command)
                    .textFieldStyle(.roundedBorder).focused($commandFocused).onSubmit(executeCommand)
                Button("Execute", action: executeCommand)
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text(response)
                .font(.title3).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                ForEach(["Brief me", "Show tasks", "Project status", "Open intelligence"], id: \.self) { suggestion in
                    Button(suggestion) { command = suggestion; executeCommand() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text("Commands are processed locally. JARVIS currently handles briefings, navigation, task counts, project status, monitoring, intelligence, weather, news, and voice settings.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(26)
        .frame(width: 650)
        .background(Color(red: 0.012, green: 0.028, blue: 0.052))
        .onAppear { commandFocused = true }
    }

    private func executeCommand() {
        let result = JarvisCommandEngine.execute(command, context: context)
        response = result.response
        onResult(result)
        if result.destination != nil && !result.shouldSpeak {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
        }
    }
}

private struct TodayTaskRow: View {
    @Bindable var task: TaskItem
    var body: some View {
        HStack(spacing: 11) {
            Button { task.isCompleted.toggle() } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title).lineLimit(1)
                    if task.isBlocked {
                        Text("BLOCKED").font(.system(size: 8, weight: .bold)).foregroundStyle(.orange)
                    }
                }
                if let dueDate = task.dueDate {
                    Text(dueDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption2).foregroundStyle(dueDate < .now ? .red : .secondary)
                }
            }
            Spacer()
            Text(task.priority.title)
                .font(.caption2)
                .foregroundStyle(task.priority == .critical ? Color.red : Color.secondary)
        }
        .padding(.vertical, 9)
    }
}

struct DashboardSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: systemImage).font(.headline)
            content
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private extension View {
    func commandSurface(cornerRadius: CGFloat) -> some View {
        background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.cyan.opacity(0.10), lineWidth: 1)
            }
    }
}
