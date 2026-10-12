import SwiftData
import SwiftUI

struct IntelligenceView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case now = "Now"
        case philippines = "Philippines"
        case watchlist = "Watchlist"
        case operations = "Operations"
        case briefings = "Briefings"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .now: "radar"
            case .philippines: "map.fill"
            case .watchlist: "scope"
            case .operations: "waveform.path.ecg.rectangle"
            case .briefings: "sparkles"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Query private var savedLocations: [SavedLocation]
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]
    @Query(sort: \ProjectItem.updatedAt, order: .reverse) private var projects: [ProjectItem]

    @AppStorage("intelligence.selectedPage") private var selectedPageRawValue = Page.now.rawValue
    @AppStorage("intelligence.weatherPresentation") private var weatherPresentation = "Map"
    @AppStorage("intelligence.newsCategory") private var newsCategoryRawValue = NewsSource.Category.philippines.rawValue
    @AppStorage("intelligence.watchlist") private var watchlistText = "AI, WordPress, technology, business"
    @AppStorage("intelligence.earthquakeThreshold") private var earthquakeThreshold = 5.0
    @AppStorage("intelligence.rainThreshold") private var rainThreshold = 70
    @AppStorage("intelligence.notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("intelligence.quietStart") private var quietStartHour = 22
    @AppStorage("intelligence.quietEnd") private var quietEndHour = 7
    @AppStorage("intelligence.readIDs") private var readIDsRaw = "[]"
    @AppStorage("intelligence.savedIDs") private var savedIDsRaw = "[]"
    @AppStorage("intelligence.dismissedIDs") private var dismissedIDsRaw = "[]"

    @State private var savedWeather: [String: WeatherSnapshot] = [:]
    @State private var regionalWeather: [String: WeatherSnapshot] = [:]
    @State private var earthquakes: [EarthquakeEvent] = []
    @State private var newsByCategory: [NewsSource.Category: [NewsArticle]] = [:]
    @State private var repositorySnapshots: [UUID: RepositorySnapshot] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLocationPicker = false
    @State private var lastRefreshedAt: Date?
    @State private var isNewsAPIEnhancementRunning = false
    @State private var changeSummary = IntelligenceChangeSummary(
        alertDelta: 0,
        overdueDelta: 0,
        storyDelta: 0,
        hasBaseline: false
    )

    private let weatherService = OpenMeteoWeatherService()
    private let earthquakeService = USGSEarthquakeService()
    private let newsService = RSSNewsService()
    private let newsAPIService = NewsAPIService()
    private let notificationService = IntelligenceNotificationService()

    private let regionalLocations = [
        SavedLocationValue(name: "Baguio", latitude: 16.4023, longitude: 120.5960),
        SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842),
        SavedLocationValue(name: "Legazpi", latitude: 13.1391, longitude: 123.7438),
        SavedLocationValue(name: "Cebu", latitude: 10.3157, longitude: 123.8854),
        SavedLocationValue(name: "Iloilo", latitude: 10.7202, longitude: 122.5621),
        SavedLocationValue(name: "Davao", latitude: 7.1907, longitude: 125.4553),
        SavedLocationValue(name: "Cagayan de Oro", latitude: 8.4542, longitude: 124.6319),
        SavedLocationValue(name: "Zamboanga", latitude: 6.9214, longitude: 122.0790)
    ]

    private var selectedPage: Binding<Page> {
        Binding(
            get: { Page(rawValue: selectedPageRawValue) ?? .now },
            set: { selectedPageRawValue = $0.rawValue }
        )
    }

    private var allNews: [NewsArticle] {
        IntelligenceEngine.deduplicated(newsByCategory.values.flatMap { $0 })
            .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
    }

    private var newsCategory: Binding<NewsSource.Category> {
        Binding(
            get: { NewsSource.Category(rawValue: newsCategoryRawValue) ?? .philippines },
            set: { newsCategoryRawValue = $0.rawValue }
        )
    }

    private var visibleNews: [NewsArticle] {
        let dismissed = decodedIDs(dismissedIDsRaw)
        return allNews.filter { !dismissed.contains($0.id) }
    }

    private var intelligenceAlerts: [IntelligenceAlert] {
        IntelligenceEngine.alerts(
            weather: Array(savedWeather.values),
            earthquakes: earthquakes,
            articles: newsByCategory[.philippines] ?? [],
            earthquakeThreshold: earthquakeThreshold,
            rainThreshold: rainThreshold
        )
    }

    private var overdueTasks: [TaskItem] {
        tasks.filter { !$0.isCompleted && ($0.dueDate ?? .distantFuture) < .now }
    }

    private var activeProjects: [ProjectItem] {
        projects.filter { !$0.isArchived && $0.status != .completed }
    }

    private var watchlistKeywords: [String] {
        watchlistText.split(separator: ",").map(String.init)
    }

    private var watchlistStories: [NewsArticle] {
        IntelligenceEngine.watchlistMatches(articles: visibleNews, keywords: watchlistKeywords)
    }

    private var savedStories: [NewsArticle] {
        let saved = decodedIDs(savedIDsRaw)
        return allNews.filter { saved.contains($0.id) }
    }

    private var primaryWeather: WeatherSnapshot? {
        let name = savedLocations.first(where: \.isPrimary)?.name ?? savedLocations.first?.name
        return name.flatMap { savedWeather[$0] } ?? savedWeather.values.first
    }

    private var briefing: String {
        BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: tasks.filter { !$0.isCompleted }.count,
                overdueTaskCount: overdueTasks.count,
                activeProjectCount: activeProjects.count,
                weather: primaryWeather,
                significantEarthquakeCount: earthquakes.filter { $0.magnitude >= earthquakeThreshold }.count
            )
        )
    }

    private var significantEarthquakes: [EarthquakeEvent] {
        earthquakes.filter { $0.magnitude >= earthquakeThreshold }
    }

    private var criticalAlertCount: Int {
        intelligenceAlerts.count { $0.severity == .critical }
    }

    private var warningAlertCount: Int {
        intelligenceAlerts.count { $0.severity == .warning }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intelligenceHeader
                intelligenceStatusRail
                pageNavigation

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 2)
                }

                switch selectedPage.wrappedValue {
                case .now: nowPage
                case .philippines: philippinesPage
                case .watchlist: watchlistPage
                case .operations: operationsPage
                case .briefings: briefingsPage
                }
            }
            .padding(28)
        }
        .background(intelligenceBackground)
        .navigationTitle("Intelligence")
        .toolbar {
            Menu {
                Button("Add Location", systemImage: "mappin.and.ellipse") { showingLocationPicker = true }
                Button("Restore Dismissed Stories", systemImage: "arrow.uturn.backward") { dismissedIDsRaw = "[]" }
                    .disabled(decodedIDs(dismissedIDsRaw).isEmpty)
            } label: {
                Label("Intelligence actions", systemImage: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            AddLocationView(existingNames: Set(savedLocations.map(\.name))) { preset in
                if preset.makePrimary { savedLocations.forEach { $0.isPrimary = false } }
                modelContext.insert(
                    SavedLocation(
                        name: preset.location.name,
                        latitude: preset.location.latitude,
                        longitude: preset.location.longitude,
                        isPrimary: preset.makePrimary
                    )
                )
                try? modelContext.save()
                Task { await refresh() }
            }
        }
        .task {
            seedDefaultLocationIfNeeded()
            await refresh()
        }
        .onChange(of: notificationsEnabled) { _, enabled in
            guard enabled else { return }
            Task {
                let granted = await notificationService.requestAuthorization()
                if !granted { notificationsEnabled = false }
            }
        }
    }

    private var intelligenceBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.012, green: 0.028, blue: 0.052), Color(nsColor: .windowBackgroundColor)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var intelligenceHeader: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Intelligence Matrix")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Live situational awareness across regions, operations, and watchlists.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(intelligenceAlerts.isEmpty ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(intelligenceAlerts.isEmpty
                     ? "No priority threats"
                     : "\(intelligenceAlerts.count) priority signal\(intelligenceAlerts.count == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(intelligenceAlerts.isEmpty ? Color.secondary : Color.orange)
            Button { Task { await refresh() } } label: {
                Label(isLoading ? "Analysing" : "Refresh Intel", systemImage: isLoading ? "hourglass" : "arrow.clockwise")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(isLoading)
        }
    }

    private var intelligenceStatusRail: some View {
        HStack(spacing: 0) {
            IntelligenceRailMetric(title: "Priority signals", value: intelligenceAlerts.count, tint: intelligenceAlerts.isEmpty ? .green : .orange)
            IntelligenceRailDivider()
            IntelligenceRailMetric(title: "Regional events", value: significantEarthquakes.count, tint: significantEarthquakes.isEmpty ? .secondary : .orange)
            IntelligenceRailDivider()
            IntelligenceRailMetric(title: "Watchlist matches", value: watchlistStories.count, tint: .cyan)
            IntelligenceRailDivider()
            IntelligenceRailMetric(title: "Overdue ops", value: overdueTasks.count, tint: overdueTasks.isEmpty ? .secondary : .red)
            IntelligenceRailDivider()
            IntelligenceRailMetric(title: "Sources loaded", value: loadedSourceCount, tint: loadedSourceCount == 5 ? .green : .secondary)
        }
        .padding(.vertical, 14)
        .intelligenceSurface(cornerRadius: 14)
    }

    private var loadedSourceCount: Int {
        if lastRefreshedAt != nil && errorMessage == nil { return 5 }
        return [
            !savedWeather.isEmpty,
            !regionalWeather.isEmpty,
            !earthquakes.isEmpty,
            newsByCategory[.philippines] != nil,
            newsByCategory[.world] != nil
        ].count(where: { $0 })
    }

    private var pageNavigation: some View {
        HStack(spacing: 6) {
            ForEach(Page.allCases) { page in
                Button { selectedPage.wrappedValue = page } label: {
                    Label(page.rawValue, systemImage: page.systemImage)
                        .font(.subheadline.weight(selectedPage.wrappedValue == page ? .semibold : .regular))
                        .foregroundStyle(selectedPage.wrappedValue == page ? Color.cyan : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            selectedPage.wrappedValue == page ? Color.cyan.opacity(0.11) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .intelligenceSurface(cornerRadius: 12)
    }

    private var nowPage: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                DashboardSection(title: "Priority signal feed", systemImage: "exclamationmark.shield.fill") {
                if isLoading && intelligenceAlerts.isEmpty {
                    ProgressView("Analyzing live sources…").controlSize(.small)
                } else if intelligenceAlerts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No current signals cross your alert thresholds", systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        Text("Weather, seismic, and Philippine news sources remain under observation.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
                } else {
                    VStack(spacing: 0) {
                        ForEach(intelligenceAlerts.prefix(10)) { alert in
                            IntelligenceAlertRow(alert: alert)
                            if alert.id != intelligenceAlerts.prefix(10).last?.id { Divider() }
                        }
                    }
                }
                }
                .frame(maxWidth: .infinity)

                situationPanel.frame(width: 300)
            }
            savedLocationsSection
        }
    }

    private var situationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Situation brief", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)

            if let weather = primaryWeather {
                HStack(spacing: 12) {
                    Image(systemName: weather.systemImage)
                        .font(.system(size: 27))
                        .foregroundStyle(.cyan)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(weather.temperature.rounded()))°C · \(weather.condition)")
                            .font(.subheadline.weight(.semibold))
                        Text(weather.locationName).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("Weather awaiting refresh", systemImage: "cloud")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Divider().opacity(0.5)

            SituationLine(label: "Critical", value: criticalAlertCount, tint: .red)
            SituationLine(label: "Warnings", value: warningAlertCount, tint: .orange)
            SituationLine(label: "Regional events", value: significantEarthquakes.count, tint: .yellow)
            SituationLine(label: "Overdue operations", value: overdueTasks.count, tint: .red)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 5) {
                Text("CHANGE DETECTION")
                    .font(.caption2.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                Text(changeSummary.sentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup("Alert policy") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Earthquake")
                            Spacer()
                            Text("M\(earthquakeThreshold, specifier: "%.1f")").monospacedDigit()
                        }
                        Slider(value: $earthquakeThreshold, in: 3...7, step: 0.5)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Rain probability")
                            Spacer()
                            Text("\(rainThreshold)%").monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(rainThreshold) },
                            set: { rainThreshold = Int($0) }
                        ), in: 40...100, step: 5)
                    }
                    Toggle("Critical notifications", isOn: $notificationsEnabled)
                    if notificationsEnabled {
                        HStack {
                            Picker("Quiet from", selection: $quietStartHour) {
                                ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                            }
                            Picker("until", selection: $quietEndHour) {
                                ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .font(.caption)

            Text("Confirm emergency decisions with PAGASA, PHIVOLCS, and local authorities.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .intelligenceSurface(cornerRadius: 14, highlighted: true)
    }

    private var philippinesPage: some View {
        Group {
            HStack {
                Label("Weather view", systemImage: "square.on.square")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Weather view", selection: $weatherPresentation) {
                    Text("My weather").tag("Dashboard")
                    Text("Philippines map").tag("Map")
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
                .labelsHidden()
            }
            .padding(14)
            .intelligenceSurface(cornerRadius: 14)
            if weatherPresentation == "Dashboard" {
                WeatherFocusDashboardView(savedLocations: savedLocations)
            } else {
                PhilippineWeatherMapView()
                regionalForecastSection
            }
            earthquakeSection
            newsSection(title: "Philippines news", articles: newsByCategory[.philippines] ?? [])
        }
    }

    private var watchlistPage: some View {
        Group {
            DashboardSection(title: "Watchlist", systemImage: "scope") {
                TextField("AI, WordPress, client names, locations", text: $watchlistText)
                    .textFieldStyle(.roundedBorder)
                Text("Separate subjects with commas. Matches are checked against all loaded Philippine and world headlines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                storyList(watchlistStories, emptyTitle: "No watchlist matches", emptyDescription: "Refresh the feeds or adjust your subjects.")
            }

            DashboardSection(title: "Saved stories", systemImage: "bookmark.fill") {
                storyList(savedStories, emptyTitle: "No saved stories", emptyDescription: "Use the bookmark button beside any headline.")
            }

            DashboardSection(title: "All news", systemImage: "newspaper") {
                Picker("News region", selection: newsCategory) {
                    ForEach(NewsSource.Category.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                storyList(
                    (newsByCategory[newsCategory.wrappedValue] ?? []).filter {
                        !decodedIDs(dismissedIDsRaw).contains($0.id)
                    },
                    emptyTitle: "News unavailable",
                    emptyDescription: "No stories are available from the selected source."
                )
            }
        }
    }

    private var operationsPage: some View {
        Group {
            HStack(spacing: 14) {
                IntelligenceMetricCard(title: "Overdue tasks", value: "\(overdueTasks.count)", systemImage: "clock.badge.exclamationmark", tint: .red)
                IntelligenceMetricCard(title: "Active projects", value: "\(activeProjects.count)", systemImage: "square.stack.3d.up.fill", tint: .orange)
                IntelligenceMetricCard(title: "Repo-connected", value: "\(projects.filter(\.hasRepository).count)", systemImage: "arrow.triangle.branch", tint: .cyan)
            }

            DashboardSection(title: "Task signals", systemImage: "checklist") {
                if overdueTasks.isEmpty {
                    Label("No overdue tasks", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    ForEach(overdueTasks.prefix(10)) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title)
                                if let dueDate = task.dueDate {
                                    Text("Due \(dueDate.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.red)
                                }
                            }
                            Spacer()
                            Text(task.priority.title).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            DashboardSection(title: "Project signals", systemImage: "waveform.path.ecg.rectangle") {
                if activeProjects.isEmpty {
                    Text("No active projects to monitor.").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(activeProjects) { project in
                            OperationalProjectRow(project: project, snapshot: repositorySnapshots[project.id])
                            if project.id != activeProjects.last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    private var briefingsPage: some View {
        Group {
            DashboardSection(title: "Current briefing", systemImage: "sparkles") {
                Text(briefing).font(.title3).textSelection(.enabled)
                HStack {
                    Button("Present Briefing", systemImage: "rectangle.inset.filled.and.person.filled") {
                        appState.requestBriefing(message: briefing)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    if let lastRefreshedAt {
                        Text("Updated \(lastRefreshedAt, style: .relative)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            DashboardSection(title: "What changed", systemImage: "arrow.triangle.2.circlepath") {
                Text(changeSummary.sentence)
                Text("Compared with the previous successful Intelligence refresh on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                IntelligenceMetricCard(title: "Priority alerts", value: "\(intelligenceAlerts.count)", systemImage: "exclamationmark.shield.fill", tint: .orange)
                IntelligenceMetricCard(title: "Watchlist matches", value: "\(watchlistStories.count)", systemImage: "scope", tint: .cyan)
                IntelligenceMetricCard(title: "Saved stories", value: "\(savedStories.count)", systemImage: "bookmark.fill", tint: .purple)
            }
        }
    }

    private var savedLocationsSection: some View {
        DashboardSection(title: "Saved locations", systemImage: "location.fill") {
            if savedLocations.isEmpty {
                ContentUnavailableView("No saved locations", systemImage: "location.slash", description: Text("Add a location for its current conditions."))
                    .frame(height: 150)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(savedLocations) { location in
                        SavedWeatherCard(
                            location: location,
                            weather: savedWeather[location.name],
                            makePrimary: {
                                savedLocations.forEach { $0.isPrimary = $0.persistentModelID == location.persistentModelID }
                                try? modelContext.save()
                            },
                            delete: {
                                modelContext.delete(location)
                                try? modelContext.save()
                            }
                        )
                    }
                }
            }
        }
    }

    private var regionalForecastSection: some View {
        DashboardSection(title: "Philippines situation overview", systemImage: "map.fill") {
            Text("Representative current conditions across Luzon, Visayas, and Mindanao")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(regionalLocations) { location in
                    let weather = regionalWeather[location.name]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(location.name).font(.headline)
                            Spacer()
                            Image(systemName: weather?.systemImage ?? "cloud").foregroundStyle(.cyan)
                        }
                        if let weather {
                            Text("\(Int(weather.temperature.rounded()))°C").font(.title2.bold().monospacedDigit())
                            Text("\(weather.condition) · \(weather.precipitationProbability)% rain")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(13)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("Forecast data: Open-Meteo. PAGASA remains the authority for official Philippine warnings.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var earthquakeSection: some View {
        DashboardSection(title: "Philippine-region earthquakes", systemImage: "waveform.path.ecg") {
            if earthquakes.isEmpty && isLoading {
                ProgressView().controlSize(.small)
            } else if earthquakes.isEmpty {
                Text("No events were reported by the current feed in the past 24 hours.").foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(earthquakes.prefix(15)) { event in
                        HStack(spacing: 14) {
                            Text("M\(event.magnitude, specifier: "%.1f")")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(event.magnitude >= earthquakeThreshold ? .orange : .primary)
                                .frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.place)
                                Text(event.occurredAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = event.detailURL { Link(destination: url) { Image(systemName: "arrow.up.right.square") } }
                        }
                        .padding(.vertical, 9)
                        if event.id != earthquakes.prefix(15).last?.id { Divider() }
                    }
                }
            }
            Text("Preliminary data: USGS. Confirm significant events with PHIVOLCS.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func newsSection(title: String, articles: [NewsArticle]) -> some View {
        DashboardSection(title: title, systemImage: "newspaper") {
            storyList(articles.filter { !decodedIDs(dismissedIDsRaw).contains($0.id) }, emptyTitle: "News unavailable", emptyDescription: "No stories are available from the loaded sources.")
        }
    }

    @ViewBuilder
    private func storyList(_ articles: [NewsArticle], emptyTitle: String, emptyDescription: String) -> some View {
        if articles.isEmpty && isLoading {
            ProgressView().controlSize(.small)
        } else if articles.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "newspaper", description: Text(emptyDescription))
                .frame(height: 150)
        } else {
            VStack(spacing: 0) {
                ForEach(articles.prefix(15)) { article in
                    NewsStoryRow(
                        article: article,
                        isRead: decodedIDs(readIDsRaw).contains(article.id),
                        isSaved: decodedIDs(savedIDsRaw).contains(article.id),
                        toggleRead: { readIDsRaw = toggledID(article.id, in: readIDsRaw) },
                        toggleSaved: { savedIDsRaw = toggledID(article.id, in: savedIDsRaw) },
                        dismiss: { dismissedIDsRaw = addingID(article.id, to: dismissedIDsRaw) }
                    )
                    if article.id != articles.prefix(15).last?.id { Divider() }
                }
            }
        }
    }

    private func seedDefaultLocationIfNeeded() {
        guard savedLocations.isEmpty else { return }
        modelContext.insert(SavedLocation(name: "Manila", latitude: 14.5995, longitude: 120.9842, isPrimary: true))
        try? modelContext.save()
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let savedValues = savedLocations.isEmpty
            ? [SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842)]
            : savedLocations.map { SavedLocationValue(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }

        async let savedRequest = try? fetchWeather(for: savedValues)
        async let regionalRequest = try? fetchWeather(for: regionalLocations)
        async let earthquakeRequest = try? earthquakeService.recentPhilippineEvents()
        async let philippinesNewsRequest = try? fetchNews(category: .philippines)
        async let worldNewsRequest = try? fetchNews(category: .world)

        let results = await (savedRequest, regionalRequest, earthquakeRequest, philippinesNewsRequest, worldNewsRequest)
        if let result = results.0 { savedWeather = result }
        if let result = results.1 { regionalWeather = result }
        if let result = results.2 { earthquakes = result }
        if let result = results.3 { newsByCategory[.philippines] = result }
        if let result = results.4 { newsByCategory[.world] = result }

        await refreshRepositorySnapshots()
        updateChangeSummary()
        lastRefreshedAt = .now

        let successes = [results.0 != nil, results.1 != nil, results.2 != nil, results.3 != nil, results.4 != nil]
        errorMessage = successes.allSatisfy { $0 }
            ? nil
            : "One or more live sources could not be refreshed. Available results remain visible."

        if notificationsEnabled {
            await notificationService.deliverNewCriticalAlerts(
                intelligenceAlerts,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour
            )
        }
        speechService.speakNewCriticalAlert(from: intelligenceAlerts)
        startNewsAPIEnhancement()
    }

    private func refreshRepositorySnapshots() async {
        let connected = projects.filter { $0.mode == .ongoing && $0.repositoryBookmarkData != nil }
        await withTaskGroup(of: (UUID, RepositorySnapshot?).self) { group in
            for project in connected {
                guard let bookmark = project.repositoryBookmarkData else { continue }
                let id = project.id
                group.addTask {
                    let inspection = try? await GitRepositoryService.inspect(bookmarkData: bookmark)
                    return (id, inspection?.snapshot)
                }
            }
            var snapshots: [UUID: RepositorySnapshot] = [:]
            for await (id, snapshot) in group {
                if let snapshot { snapshots[id] = snapshot }
            }
            repositorySnapshots = snapshots
        }
    }

    private func fetchWeather(for locations: [SavedLocationValue]) async throws -> [String: WeatherSnapshot] {
        try await withThrowingTaskGroup(of: WeatherSnapshot.self) { group in
            for location in locations { group.addTask { try await weatherService.currentWeather(for: location) } }
            var output: [String: WeatherSnapshot] = [:]
            for try await snapshot in group { output[snapshot.locationName] = snapshot }
            return output
        }
    }

    private func fetchNews(category: NewsSource.Category) async throws -> [NewsArticle] {
        guard let source = NewsSource.defaults.first(where: { $0.category == category }) else { return [] }
        return try await newsService.articles(from: source)
    }

    @MainActor
    private func startNewsAPIEnhancement() {
        guard !isNewsAPIEnhancementRunning else { return }
        isNewsAPIEnhancementRunning = true
        Task {
            let apiKey = await Task.detached(priority: .utility) {
                NewsAPIKeyStore().read()
            }.value
            guard let apiKey else {
                isNewsAPIEnhancementRunning = false
                return
            }

            async let philippines = try? newsAPIService.articles(category: .philippines, apiKey: apiKey)
            async let world = try? newsAPIService.articles(category: .world, apiKey: apiKey)
            let results = await (philippines, world)
            if let articles = results.0, !articles.isEmpty { newsByCategory[.philippines] = articles }
            if let articles = results.1, !articles.isEmpty { newsByCategory[.world] = articles }
            isNewsAPIEnhancementRunning = false
        }
    }

    private func updateChangeSummary() {
        let defaults = UserDefaults.standard
        let hadBaseline = defaults.object(forKey: "intelligence.baselineDate") != nil
        changeSummary = IntelligenceChangeSummary(
            alertDelta: intelligenceAlerts.count - defaults.integer(forKey: "intelligence.baselineAlerts"),
            overdueDelta: overdueTasks.count - defaults.integer(forKey: "intelligence.baselineOverdue"),
            storyDelta: allNews.count - defaults.integer(forKey: "intelligence.baselineStories"),
            hasBaseline: hadBaseline
        )
        defaults.set(intelligenceAlerts.count, forKey: "intelligence.baselineAlerts")
        defaults.set(overdueTasks.count, forKey: "intelligence.baselineOverdue")
        defaults.set(allNews.count, forKey: "intelligence.baselineStories")
        defaults.set(Date.now.timeIntervalSince1970, forKey: "intelligence.baselineDate")
    }

    private func hourLabel(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now)
    }

    private func decodedIDs(_ raw: String) -> Set<String> {
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(values)
    }

    private func toggledID(_ id: String, in raw: String) -> String {
        var values = decodedIDs(raw)
        if values.contains(id) {
            values.remove(id)
        } else {
            values.insert(id)
        }
        return encodedIDs(values)
    }

    private func addingID(_ id: String, to raw: String) -> String {
        var values = decodedIDs(raw)
        values.insert(id)
        return encodedIDs(values)
    }

    private func encodedIDs(_ values: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(Array(values).sorted()) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct IntelligenceMetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                Text(title).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: systemImage).font(.title2).foregroundStyle(tint)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct IntelligenceRailMetric: View {
    let title: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
    }
}

private struct IntelligenceRailDivider: View {
    var body: some View { Divider().frame(height: 34) }
}

private struct SituationLine: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(value > 0 ? tint : Color.secondary)
        }
        .font(.subheadline)
    }
}

private extension View {
    func intelligenceSurface(cornerRadius: CGFloat, highlighted: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(highlighted ? 0.72 : 0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(highlighted ? Color.cyan.opacity(0.30) : Color.white.opacity(0.07), lineWidth: 1)
                )
        )
    }
}

private struct IntelligenceAlertRow: View {
    let alert: IntelligenceAlert

    private var color: Color {
        switch alert.severity {
        case .information: .secondary
        case .advisory: .yellow
        case .warning: .orange
        case .critical: .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity >= .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title).font(.headline)
                Text(alert.detail).font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Text(alert.severity.title.uppercased())
                    Text("·")
                    Text(alert.source)
                    Text("·")
                    Text(alert.occurredAt, style: .relative)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
            }
            Spacer()
            if let destination = alert.destination {
                Link(destination: destination) { Image(systemName: "arrow.up.right.square") }
            }
        }
        .padding(.vertical, 10)
    }
}

private struct NewsStoryRow: View {
    let article: NewsArticle
    let isRead: Bool
    let isSaved: Bool
    let toggleRead: () -> Void
    let toggleSaved: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Link(destination: article.link) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(article.title)
                        .fontWeight(isRead ? .regular : .semibold)
                        .foregroundStyle(isRead ? .secondary : .primary)
                        .multilineTextAlignment(.leading)
                    HStack {
                        Text(article.sourceName)
                        if let publishedAt = article.publishedAt {
                            Text("·")
                            Text(publishedAt, style: .relative)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: toggleRead) { Image(systemName: isRead ? "envelope.open.fill" : "envelope") }
                .buttonStyle(.plain).help(isRead ? "Mark unread" : "Mark read")
            Button(action: toggleSaved) { Image(systemName: isSaved ? "bookmark.fill" : "bookmark") }
                .buttonStyle(.plain).help(isSaved ? "Remove bookmark" : "Save story")
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.plain).help("Dismiss story")
            Link(destination: article.link) { Image(systemName: "arrow.up.right") }
        }
        .padding(.vertical, 10)
    }
}

private struct OperationalProjectRow: View {
    let project: ProjectItem
    let snapshot: RepositorySnapshot?

    private var health: RepositoryHealth {
        RepositoryHealth.evaluate(status: project.status, dueDate: project.dueDate, snapshot: snapshot)
    }

    private var color: Color {
        switch health {
        case .healthy: .green
        case .quiet: .yellow
        case .attention: .orange
        case .blocked: .red
        case .setupNeeded: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                Text(project.mode == .ongoing
                     ? "\(health.title) · \(snapshot?.branch ?? "repository not connected")"
                     : "\(project.status.title) · \(project.progress.formatted(.percent.precision(.fractionLength(0)))) complete")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let dueDate = project.dueDate {
                Text(dueDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(dueDate < .now ? .red : .secondary)
            }
        }
        .padding(.vertical, 9)
    }
}

private struct SavedWeatherCard: View {
    let location: SavedLocation
    let weather: WeatherSnapshot?
    let makePrimary: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(location.name).font(.headline)
                Spacer()
                Button(action: makePrimary) {
                    Image(systemName: location.isPrimary ? "star.fill" : "star")
                        .foregroundStyle(location.isPrimary ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Make primary location")
                Menu {
                    Button("Remove", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
            }

            if let weather {
                HStack {
                    Image(systemName: weather.systemImage)
                        .font(.title)
                        .foregroundStyle(.cyan)
                    Text("\(Int(weather.temperature.rounded()))°C")
                        .font(.title.bold().monospacedDigit())
                }
                Text("\(weather.condition) · feels like \(Int(weather.apparentTemperature.rounded()))°")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AddLocationView: View {
    struct Selection {
        let location: SavedLocationValue
        let makePrimary: Bool
    }

    @Environment(\.dismiss) private var dismiss
    let existingNames: Set<String>
    let onAdd: (Selection) -> Void

    @State private var selectedName = "Cebu"
    @State private var makePrimary = false

    private let presets = [
        SavedLocationValue(name: "Baguio", latitude: 16.4023, longitude: 120.5960),
        SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842),
        SavedLocationValue(name: "Legazpi", latitude: 13.1391, longitude: 123.7438),
        SavedLocationValue(name: "Puerto Princesa", latitude: 9.7392, longitude: 118.7353),
        SavedLocationValue(name: "Cebu", latitude: 10.3157, longitude: 123.8854),
        SavedLocationValue(name: "Iloilo", latitude: 10.7202, longitude: 122.5621),
        SavedLocationValue(name: "Tacloban", latitude: 11.2447, longitude: 125.0039),
        SavedLocationValue(name: "Davao", latitude: 7.1907, longitude: 125.4553),
        SavedLocationValue(name: "Cagayan de Oro", latitude: 8.4542, longitude: 124.6319),
        SavedLocationValue(name: "Zamboanga", latitude: 6.9214, longitude: 122.0790)
    ]

    private var availablePresets: [SavedLocationValue] {
        presets.filter { !existingNames.contains($0.name) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if availablePresets.isEmpty {
                    Text("All preset locations are already saved.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Location", selection: $selectedName) {
                        ForEach(availablePresets) { location in
                            Text(location.name).tag(location.name)
                        }
                    }
                    Toggle("Make this my primary location", isOn: $makePrimary)
                }
            }
            .padding(20)
            .navigationTitle("Add Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let selected = availablePresets.first(where: { $0.name == selectedName }) ?? availablePresets.first
                        if let selected { onAdd(Selection(location: selected, makePrimary: makePrimary)) }
                        dismiss()
                    }
                    .disabled(availablePresets.isEmpty)
                }
            }
        }
        .frame(width: 430, height: 260)
        .onAppear {
            if let first = availablePresets.first, !availablePresets.contains(where: { $0.name == selectedName }) {
                selectedName = first.name
            }
        }
    }
}
