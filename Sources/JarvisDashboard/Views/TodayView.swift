import AppKit
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
    @State private var hasFreshWeather = false
    @State private var earthquakes: [EarthquakeEvent] = []
    @State private var monitoringSites: [String: MonitoringSite] = [:]
    @State private var hasLoadedMonitoring = false
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
        let unhealthy = monitoredProjects.filter {
            let state = monitoringHealth(for: $0).state
            return state == .down || state == .critical || state == .needsAttention
        }
        let unverified = monitoredProjects.filter {
            let state = monitoringHealth(for: $0).state
            return state == .stale || state == .awaitingChecks
        }
        let maintenance = monitoredProjects.filter { monitoringHealth(for: $0).state == .maintenance }
        let weatherReport = (hasFreshWeather ? weather : nil).map {
            "In \($0.locationName), it is \(Int($0.temperature.rounded()))°C and \($0.condition.lowercased()). Rain probability is \($0.precipitationProbability)%."
        }
        return JarvisCommandContext(
            briefing: briefing,
            pendingTasks: pendingTasks.count,
            overdueTasks: overdueTasks.count,
            activeProjects: operationalProjects.count,
            monitoredSites: monitoredProjects.count,
            unhealthySites: unhealthy.count,
            unverifiedSites: unverified.count,
            maintenanceSites: maintenance.count,
            monitoringAvailable: hasLoadedMonitoring,
            priorityTask: TaskQueueEngine.focusTask(from: pendingTasks.filter { !$0.isBlocked })?.title,
            blockedTaskNames: TaskQueueEngine.sorted(blockedTasks).map(\.title),
            waitingProjectNames: waitingProjects.map(\.name),
            unhealthySiteNames: unhealthy.map(\.name),
            weatherReport: weatherReport,
            projects: projects.map { project in
                let projectTasks = tasks.filter { $0.projectID == project.id && !$0.isCompleted }
                let site = hasLoadedMonitoring ? monitoringSite(for: project) : nil
                let siteHealth: String
                let monitoringSource: String
                if !project.hasMonitoringSite {
                    siteHealth = "Not connected"
                    monitoringSource = "no monitored site"
                } else if !hasLoadedMonitoring {
                    siteHealth = "Unavailable — monitoring could not be refreshed"
                    monitoringSource = "monitoring unavailable"
                } else {
                    siteHealth = site.map { MonitoringHealth.evaluate(site: $0, connected: true).label }
                        ?? "Unavailable — site was not returned by Monitoring API"
                    monitoringSource = "Monitoring API"
                }
                return JarvisProjectBrief(
                    id: project.id,
                    name: project.name,
                    client: project.client,
                    status: project.status.title,
                    updatedAt: project.updatedAt,
                    nextAction: project.nextAction,
                    openTasks: projectTasks.count,
                    overdueTasks: projectTasks.count { ($0.dueDate ?? .distantFuture) < .now },
                    blockedTasks: projectTasks.count(where: \.isBlocked),
                    siteHealth: siteHealth,
                    siteCheckedAt: site?.lastCheckAt,
                    monitoringSource: monitoringSource
                )
            }
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
            JarvisCommandConsole(
                context: commandContext,
                onResult: { result in
                    if let destination = result.destination { appState.selection = destination }
                    if result.shouldSpeak { speechService.speak(result.response) }
                },
                onOpenProject: { projectID in
                    showingCommandConsole = false
                    appState.openProject(projectID)
                }
            )
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

        hasFreshWeather = newWeather != nil
        hasLoadedMonitoring = newMonitoringSites != nil
        if let newWeather { weather = newWeather }
        if let newEarthquakes { earthquakes = newEarthquakes }
        if let newMonitoringSites {
            // A duplicate site ID from the API must not crash; keep the last one, as ProjectsView does.
            monitoringSites = Dictionary(newMonitoringSites.map { ($0.id, $0) }) { _, latest in latest }
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
    @AppStorage("icm.vaultPath") private var vaultPath = ""
    @FocusState private var commandFocused: Bool
    @State private var command = ""
    @State private var response = "Awaiting your command, Sir."
    @State private var lastResult: JarvisCommandResult?
    @State private var preparedRoute: ICMPreparedRoute?
    @State private var activityNoteURL: URL?
    @State private var captureStatus: String?
    let context: JarvisCommandContext
    let onResult: (JarvisCommandResult) -> Void
    let onOpenProject: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("JARVIS Command Console", systemImage: "waveform.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.cyan)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 10) {
                TextField("Ask about a project or describe work to route…", text: $command)
                    .textFieldStyle(.roundedBorder).focused($commandFocused).onSubmit(executeCommand)
                Button("Execute", action: executeCommand)
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(preparedRoute?.route.name ?? lastResult?.card?.title ?? "JARVIS RESPONSE", systemImage: "sparkles.rectangle.stack")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.cyan)
                        Spacer()
                        if let card = lastResult?.card {
                            Text(card.status).font(.caption.weight(.semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.cyan.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(response).font(.subheadline).textSelection(.enabled)
                    if let preparedRoute {
                        Divider()
                        LabeledContent("Project", value: preparedRoute.projectURL.path)
                            .font(.caption).textSelection(.enabled)
                        LabeledContent("Context", value: preparedRoute.contextURL.path)
                            .font(.caption).textSelection(.enabled)
                        Text("Graphify hints: \(preparedRoute.graphURLs.count) · verify each connection in source")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Copy agent handoff", systemImage: "doc.on.doc") {
                                NSPasteboard.general.clearContents()
                                let activityInstruction = activityNoteURL.map {
                                    "\nActivity note: \($0.path)\nUpdate this note with work performed, source files, verification, outcome and next action before finishing."
                                } ?? ""
                                NSPasteboard.general.setString(preparedRoute.handoff + activityInstruction, forType: .string)
                            }
                            Button("Open project", systemImage: "folder") {
                                NSWorkspace.shared.open(preparedRoute.projectURL)
                            }
                            Button("Open context", systemImage: "doc.text") {
                                NSWorkspace.shared.open(preparedRoute.contextURL)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    if let card = lastResult?.card {
                        Divider()
                        ForEach(card.facts, id: \.self) { fact in
                            Text(fact).font(.subheadline).textSelection(.enabled)
                        }
                        HStack {
                            Text(card.source).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let projectID = card.projectID {
                                Button("View project", systemImage: "arrow.up.right.square") {
                                    onOpenProject(projectID)
                                }
                                .buttonStyle(.borderedProminent).tint(.cyan)
                            }
                        }
                    } else if preparedRoute == nil {
                        Text("Source: local dashboard snapshot")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let captureStatus {
                        Text(captureStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 340)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(["Brief me", "What needs attention?", "What should I work on?", "Are my sites healthy?"], id: \.self) { suggestion in
                    Button(suggestion) { command = suggestion; executeCommand() }
                        .buttonStyle(.bordered).controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Ask about a project…") {
                    command = "How is "
                    commandFocused = true
                }
                .buttonStyle(.bordered).controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Work requests use the local ICM vault route and create a PARA project activity note. Copy the handoff into Codex or Claude. Every submitted prompt is saved locally when the vault is available; nothing is sent to an LLM from this console.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(26)
        .frame(width: 650)
        .background(Color(red: 0.012, green: 0.028, blue: 0.052))
        .onAppear { commandFocused = true }
    }

    private func executeCommand() {
        let prompt = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        let vaultURL = ICMRoutingService.vaultURL(configuredPath: vaultPath)
        preparedRoute = nil
        activityNoteURL = nil
        captureStatus = nil
        if ICMRoutingService.isWorkRequest(prompt) {
            do {
                let route = try ICMRoutingService.prepare(prompt: prompt, vaultURL: vaultURL)
                preparedRoute = route
                lastResult = nil
                response = route.map { "Routed to \($0.route.name). The agent handoff is ready to copy." }
                    ?? "No project route matched. Add an alias in ICM/routes.json or name a configured project."
            } catch {
                lastResult = nil
                response = error.localizedDescription
            }
            capture(prompt: prompt, route: preparedRoute?.route, vaultURL: vaultURL)
            return
        }
        let result = JarvisCommandEngine.execute(prompt, context: context)
        response = result.response
        lastResult = result
        onResult(result)
        capture(prompt: prompt, route: nil, vaultURL: vaultURL)
        if result.response.contains("Opening") && result.destination != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
        }
    }

    private func capture(prompt: String, route: ICMRoute?, vaultURL: URL) {
        do {
            let file = try ICMRoutingService.capture(prompt: prompt, route: route, vaultURL: vaultURL)
            if let route {
                do {
                    activityNoteURL = try ICMRoutingService.recordActivity(
                        prompt: prompt, route: route, rawPromptURL: file, vaultURL: vaultURL
                    )
                    captureStatus = "Prompt and PARA activity note saved in Obsidian."
                } catch {
                    captureStatus = "Prompt saved; activity note was not created: \(error.localizedDescription)"
                }
            } else {
                captureStatus = "Prompt saved in Obsidian: \(file.lastPathComponent)"
            }
        } catch {
            captureStatus = "Prompt was not saved: \(error.localizedDescription)"
        }
    }
}

private struct TodayTaskRow: View {
    @Bindable var task: TaskItem
    var body: some View {
        HStack(spacing: 11) {
            Button { TaskStore.setCompleted(task, !task.isCompleted) } label: {
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
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                )
        )
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
