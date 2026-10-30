import SwiftData
import SwiftUI

struct IntelligenceView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case now = "Now"
        case philippines = "Philippines"
        case watchlist = "Watchlist"
        case briefings = "Briefings"

        var id: Self { self }

        var systemImage: String {
            switch self {
            case .now: "radar"
            case .philippines: "map.fill"
            case .watchlist: "scope"
            case .briefings: "sparkles"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
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

    @ObservedObject private var feed = IntelligenceFeed.shared
    @State private var showingLocationPicker = false
    @State private var changeSummary = IntelligenceChangeSummary(
        alertDelta: 0,
        overdueDelta: 0,
        storyDelta: 0,
        hasBaseline: false
    )

    private let notificationService = IntelligenceNotificationService()

    // Fetched by IntelligenceFeed for the app's lifetime; this view only reads them.
    private var savedWeather: [String: WeatherSnapshot] { feed.savedWeather }
    private var regionalWeather: [String: WeatherSnapshot] { feed.regionalWeather }
    private var earthquakes: [EarthquakeEvent] { feed.earthquakes }
    private var newsByCategory: [NewsSource.Category: [NewsArticle]] { feed.newsByCategory }
    private var isLoading: Bool { feed.isRefreshing }
    private var errorMessage: String? { feed.errorMessage }
    private var newsAPIMessage: String? { feed.newsAPIMessage }
    private var lastRefreshedAt: Date? { feed.lastRefreshedAt }
    private var regionalLocations: [SavedLocationValue] { IntelligenceFeed.regionalLocations }

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
        let sites = SiteMonitor.shared.briefingSites(for: projects)
        return BriefingComposer().compose(
            BriefingInput(
                pendingTaskCount: tasks.filter { !$0.isCompleted }.count,
                overdueTaskCount: overdueTasks.count,
                activeProjectCount: activeProjects.count,
                weather: primaryWeather,
                significantEarthquakeCount: earthquakes.filter { $0.magnitude >= earthquakeThreshold }.count,
                downSiteNames: sites.down,
                slowSiteNames: sites.slow,
                newLeadCount: LeadMonitor.shared.unreadCount()
            )
        )
    }

    private var significantEarthquakes: [EarthquakeEvent] {
        earthquakes.filter { $0.magnitude >= earthquakeThreshold }
    }

    /// The alerts as shown: earthquakes close in place and time become one row. Notifications, speech,
    /// and the state snapshot still use the individual alerts.
    private var feedItems: [FeedItem] {
        var items = intelligenceAlerts.filter { $0.kind != .earthquake }.map { FeedItem(alert: $0, cluster: nil) }
        for cluster in IntelligenceEngine.clusters(significantEarthquakes) {
            let ids = Set(cluster.events.map { "earthquake-\($0.id)" })
            let members = intelligenceAlerts.filter { ids.contains($0.id) }
            if cluster.events.count == 1, let alert = members.first {
                items.append(FeedItem(alert: alert, cluster: nil))
                continue
            }
            let strongest = cluster.strongest
            items.append(FeedItem(
                alert: IntelligenceAlert(
                    id: "earthquake-cluster-\(strongest.id)",
                    title: "\(cluster.events.count) earthquakes near \(cluster.area)",
                    detail: "Largest M\(strongest.magnitude.formatted(.number.precision(.fractionLength(1)))) · \(strongest.place)",
                    severity: members.map(\.severity).max() ?? .warning,
                    kind: .earthquake,
                    occurredAt: cluster.latest,
                    source: "USGS",
                    destination: strongest.detailURL
                ),
                cluster: cluster
            ))
        }
        return items.sorted {
            if $0.alert.severity != $1.alert.severity { return $0.alert.severity > $1.alert.severity }
            return $0.alert.occurredAt > $1.alert.occurredAt
        }
    }

    private var philippineHeadlines: [NewsArticle] {
        let dismissed = decodedIDs(dismissedIDsRaw)
        return (newsByCategory[.philippines] ?? []).filter { !dismissed.contains($0.id) }
    }

    private var otherSavedLocations: [SavedLocation] {
        let primaryName = primaryWeather?.locationName
        return savedLocations.filter { $0.name != primaryName }
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
                if let newsAPIMessage {
                    Label("NewsAPI: \(newsAPIMessage) Showing feed headlines instead.", systemImage: "newspaper")
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 2)
                }

                switch selectedPage.wrappedValue {
                case .now: nowPage
                case .philippines: philippinesPage
                case .watchlist: watchlistPage
                case .briefings: briefingsPage
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 1_180)
            .frame(maxWidth: .infinity)
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
            await feed.refreshIfStale()
            updateChangeSummary()
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Intelligence")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Earthquakes, weather, and news for the Philippines and your watchlist.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let signals = feedItems.count
            Label(signals == 0 ? "No priority signals" : "\(signals) priority signal\(signals == 1 ? "" : "s")",
                  systemImage: signals == 0 ? "checkmark.shield.fill" : "exclamationmark.circle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(signals == 0 ? Color.green : Color.orange)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background((signals == 0 ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            Button { Task { await refresh() } } label: {
                Label(isLoading ? "Refreshing" : "Refresh", systemImage: isLoading ? "hourglass" : "arrow.clockwise")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.cyan)
            .disabled(isLoading)
        }
    }

    private var intelligenceStatusRail: some View {
        HStack(spacing: 0) {
            IntelligenceRailMetric(title: "Priority signals", value: "\(feedItems.count)", tint: feedItems.isEmpty ? .green : .orange)
            IntelligenceRailDivider()
            IntelligenceRailMetric(title: "Earthquakes ≥ M\(earthquakeThreshold.formatted(.number.precision(.fractionLength(1))))",
                                   value: "\(significantEarthquakes.count)", tint: significantEarthquakes.isEmpty ? .secondary : .orange)
            IntelligenceRailDivider()
            IntelligenceRailMetric(title: "Watchlist matches", value: "\(watchlistStories.count)", tint: watchlistStories.isEmpty ? .secondary : .cyan)
            IntelligenceRailDivider()
            IntelligenceRailMetric(title: sourcesCaption, value: "\(loadedSourceCount)/5",
                                   tint: loadedSourceCount == 5 ? .green : .orange)
        }
        .padding(.vertical, 18)
        .intelligenceSurface(cornerRadius: 16)
    }

    private var sourcesCaption: String {
        guard let lastRefreshedAt else { return isLoading ? "Sources · loading" : "Sources" }
        return "Sources · updated \(lastRefreshedAt.formatted(.relative(presentation: .named)))"
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
        Picker("Page", selection: selectedPage) {
            ForEach(Page.allCases) { page in
                Label(page.rawValue, systemImage: page.systemImage).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 520)
    }

    private var nowPage: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 16) {
                DashboardSection(title: "Priority signals", systemImage: "exclamationmark.shield.fill") {
                    if isLoading && feedItems.isEmpty {
                        ProgressView("Checking live sources…").controlSize(.small)
                    } else if feedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Nothing crosses your alert thresholds", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("Weather, earthquakes, and Philippine news remain under observation.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(feedItems.prefix(10)) { item in
                                IntelligenceAlertRow(alert: item.alert, cluster: item.cluster)
                                if item.id != feedItems.prefix(10).last?.id { Divider() }
                            }
                        }
                    }
                    Text("Preliminary data. Confirm emergency decisions with PAGASA, PHIVOLCS, and local authorities.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if !watchlistStories.isEmpty {
                    DashboardSection(title: "Watchlist matches", systemImage: "scope") {
                        storyList(Array(watchlistStories.prefix(3)), emptyTitle: "", emptyDescription: "")
                        moreButton("All watchlist matches", page: .watchlist)
                    }
                }

                DashboardSection(title: "Philippine headlines", systemImage: "newspaper") {
                    storyList(Array(philippineHeadlines.prefix(5)), emptyTitle: "News unavailable",
                              emptyDescription: "No stories are available from the loaded sources.")
                    if philippineHeadlines.count > 5 {
                        moreButton("More Philippine news", page: .philippines)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            conditionsPanel.frame(width: 300)
        }
    }

    private func moreButton(_ title: String, page: Page) -> some View {
        Button { selectedPage.wrappedValue = page } label: {
            Label(title, systemImage: "arrow.right")
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.cyan)
    }

    /// The primary location's weather, then the other saved locations as compact rows.
    private var conditionsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Conditions", systemImage: "cloud.sun")
                .font(.headline)

            if let weather = primaryWeather {
                HStack(spacing: 12) {
                    Image(systemName: weather.systemImage)
                        .font(.system(size: 30))
                        .foregroundStyle(.cyan)
                        .frame(width: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Int(weather.temperature.rounded()))°C")
                            .font(.title.bold().monospacedDigit())
                        Text("\(weather.condition) · feels like \(Int(weather.apparentTemperature.rounded()))°")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(weather.locationName).font(.caption.weight(.semibold))
                    }
                }
            } else {
                Label("Weather awaiting refresh", systemImage: "cloud")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if !otherSavedLocations.isEmpty {
                Divider().opacity(0.5)
                VStack(spacing: 2) {
                    ForEach(otherSavedLocations) { location in
                        SavedLocationRow(
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

            Button { showingLocationPicker = true } label: {
                Label("Add Location", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.cyan)

            Text("Forecast data: Open-Meteo. Right-click a location to make it primary or remove it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .intelligenceSurface(cornerRadius: 14, highlighted: true)
    }

    private var alertPolicySection: some View {
        DashboardSection(title: "Alert policy", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Earthquakes from")
                    Spacer()
                    Text("M\(earthquakeThreshold, specifier: "%.1f")").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $earthquakeThreshold, in: 3...7, step: 0.5)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Rain probability from")
                    Spacer()
                    Text("\(rainThreshold)%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { Double(rainThreshold) },
                    set: { rainThreshold = Int($0) }
                ), in: 40...100, step: 5)
            }
            Toggle("Notify me about critical signals", isOn: $notificationsEnabled)
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

            alertPolicySection

            HStack(spacing: 14) {
                IntelligenceMetricCard(title: "Priority signals", value: "\(feedItems.count)", systemImage: "exclamationmark.shield.fill", tint: .orange)
                IntelligenceMetricCard(title: "Watchlist matches", value: "\(watchlistStories.count)", systemImage: "scope", tint: .cyan)
                IntelligenceMetricCard(title: "Saved stories", value: "\(savedStories.count)", systemImage: "bookmark.fill", tint: .purple)
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
        await feed.refresh(forceNewsAPI: true)
        updateChangeSummary()
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
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.monospacedDigit().weight(.bold))
                .foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

private struct IntelligenceRailDivider: View {
    var body: some View { Divider().frame(height: 38) }
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

private struct FeedItem: Identifiable {
    let alert: IntelligenceAlert
    /// Set when the row stands for several nearby earthquakes.
    let cluster: EarthquakeCluster?

    var id: String { alert.id }
}

private struct IntelligenceAlertRow: View {
    let alert: IntelligenceAlert
    var cluster: EarthquakeCluster?
    @State private var isExpanded = false

    private var color: Color {
        switch alert.severity {
        case .information: .secondary
        case .advisory: .yellow
        case .warning: .orange
        case .critical: .red
        }
    }

    /// "USGS" from "USGS · confirm with PHIVOLCS"; the caveat is stated once under the feed.
    private var sourceName: String {
        alert.source.components(separatedBy: " · ").first ?? alert.source
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: alert.severity >= .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(alert.title).font(.headline)
                Text(alert.detail).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(alert.severity.title.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                    Text("·")
                    Text(sourceName)
                    Text("·")
                    Text(alert.occurredAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let cluster {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
                    } label: {
                        Label(isExpanded ? "Hide events" : "Show \(cluster.events.count) events",
                              systemImage: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                    .padding(.top, 2)
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(cluster.events) { event in
                                HStack(spacing: 10) {
                                    Text("M\(event.magnitude, specifier: "%.1f")")
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .frame(width: 36, alignment: .leading)
                                    Text(event.place).font(.caption).foregroundStyle(.secondary)
                                    Spacer(minLength: 8)
                                    Text(event.occurredAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let url = event.detailURL {
                                        Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                                            .help("Open on USGS")
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            Spacer()
            if cluster == nil, let destination = alert.destination {
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

/// A saved location other than the primary one: name and conditions on one line.
private struct SavedLocationRow: View {
    let location: SavedLocation
    let weather: WeatherSnapshot?
    let makePrimary: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: weather?.systemImage ?? "cloud")
                .foregroundStyle(.cyan)
                .frame(width: 22)
            Text(location.name).font(.subheadline.weight(.medium))
            Spacer(minLength: 8)
            if let weather {
                Text("\(Int(weather.temperature.rounded()))° · \(weather.condition)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Make Primary", systemImage: "star", action: makePrimary)
            Button("Remove", systemImage: "trash", role: .destructive, action: delete)
        }
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
