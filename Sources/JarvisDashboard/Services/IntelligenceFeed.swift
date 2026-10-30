import Foundation
import SwiftData

/// Weather, earthquakes, and news for Today, Intelligence, and state.json, fetched for the app's lifetime
/// (window open or not). Views read this instead of fetching, so alerts and the snapshot stay current
/// with the dashboard closed.
@MainActor
final class IntelligenceFeed: ObservableObject {
    static let shared = IntelligenceFeed()
    static let interval: Duration = .seconds(30 * 60)
    /// A view opened within this long of the last refresh shows what is held instead of fetching again.
    static let freshness: TimeInterval = 10 * 60
    /// NewsAPI's free plan allows 100 requests a day and each refresh makes two, so it is asked at most every 2 hours.
    static let newsAPIInterval: TimeInterval = 2 * 60 * 60
    static let fallbackLocation = SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842)
    static let regionalLocations = [
        SavedLocationValue(name: "Baguio", latitude: 16.4023, longitude: 120.5960),
        SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842),
        SavedLocationValue(name: "Legazpi", latitude: 13.1391, longitude: 123.7438),
        SavedLocationValue(name: "Cebu", latitude: 10.3157, longitude: 123.8854),
        SavedLocationValue(name: "Iloilo", latitude: 10.7202, longitude: 122.5621),
        SavedLocationValue(name: "Davao", latitude: 7.1907, longitude: 125.4553),
        SavedLocationValue(name: "Cagayan de Oro", latitude: 8.4542, longitude: 124.6319),
        SavedLocationValue(name: "Zamboanga", latitude: 6.9214, longitude: 122.0790)
    ]

    @Published private(set) var savedWeather: [String: WeatherSnapshot] = [:]
    @Published private(set) var regionalWeather: [String: WeatherSnapshot] = [:]
    @Published private(set) var earthquakes: [EarthquakeEvent] = []
    @Published private(set) var newsByCategory: [NewsSource.Category: [NewsArticle]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshedAt: Date?
    /// When the saved locations' weather last arrived; Today only reports weather this recent.
    @Published private(set) var weatherUpdatedAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var newsAPIMessage: String?

    private let weatherService = OpenMeteoWeatherService()
    private let earthquakeService = USGSEarthquakeService()
    private let newsService = RSSNewsService()
    private let newsAPIService = NewsAPIService()
    private let notificationService = IntelligenceNotificationService()
    private let defaults: UserDefaults
    private var context: ModelContext?
    /// NewsAPI headlines win over the RSS feed until the next NewsAPI fetch replaces them.
    private var newsAPIArticles: [NewsSource.Category: [NewsArticle]] = [:]
    private var newsAPIFetchedAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    // MARK: Derived values

    var alerts: [IntelligenceAlert] {
        IntelligenceEngine.alerts(
            weather: Array(savedWeather.values),
            earthquakes: earthquakes,
            articles: newsByCategory[.philippines] ?? [],
            earthquakeThreshold: earthquakeThreshold,
            rainThreshold: rainThreshold
        )
    }

    var earthquakeThreshold: Double {
        defaults.object(forKey: "intelligence.earthquakeThreshold") == nil ? 5.0 : defaults.double(forKey: "intelligence.earthquakeThreshold")
    }

    var rainThreshold: Int {
        defaults.object(forKey: "intelligence.rainThreshold") == nil ? 70 : defaults.integer(forKey: "intelligence.rainThreshold")
    }

    /// The primary saved location's weather, or any saved location's when the primary has none yet.
    func weather(for locationName: String) -> WeatherSnapshot? {
        savedWeather[locationName] ?? savedWeather.values.first
    }

    var hasFreshWeather: Bool {
        weatherUpdatedAt.map { Date.now.timeIntervalSince($0) < 60 * 60 } ?? false
    }

    // MARK: Refreshing

    /// Refreshes every 30 minutes.
    func run() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: Self.interval)
        }
    }

    /// After sleep the network takes a moment to return.
    func refreshAfterWake() {
        Task {
            try? await Task.sleep(for: .seconds(20))
            await refresh()
        }
    }

    /// For a view appearing: fetches only when nothing recent is held.
    func refreshIfStale() async {
        if let lastRefreshedAt, Date.now.timeIntervalSince(lastRefreshedAt) < Self.freshness { return }
        await refresh()
    }

    /// `forceNewsAPI` is for the Refresh button: it asks NewsAPI even within its 2-hour spacing.
    func refresh(forceNewsAPI: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let saved = savedLocations()
        async let savedRequest = try? fetchWeather(for: saved)
        async let regionalRequest = try? fetchWeather(for: Self.regionalLocations)
        async let earthquakeRequest = try? earthquakeService.recentPhilippineEvents()
        async let philippinesRequest = try? fetchNews(category: .philippines)
        async let worldRequest = try? fetchNews(category: .world)
        let results = await (savedRequest, regionalRequest, earthquakeRequest, philippinesRequest, worldRequest)

        if let result = results.0 {
            savedWeather = result
            weatherUpdatedAt = .now
        }
        if let result = results.1 { regionalWeather = result }
        if let result = results.2 { earthquakes = result }
        if let result = results.3 { newsByCategory[.philippines] = result }
        if let result = results.4 { newsByCategory[.world] = result }

        if forceNewsAPI || newsAPIFetchedAt.map({ Date.now.timeIntervalSince($0) >= Self.newsAPIInterval }) ?? true {
            await fetchNewsAPI()
        }
        for (category, articles) in newsAPIArticles where !articles.isEmpty { newsByCategory[category] = articles }

        lastRefreshedAt = .now
        let succeeded = [results.0 != nil, results.1 != nil, results.2 != nil, results.3 != nil, results.4 != nil]
        errorMessage = succeeded.allSatisfy { $0 }
            ? nil
            : "One or more live sources could not be refreshed. Available results remain visible."

        let primary = saved.first ?? Self.fallbackLocation
        let snapshots = StateSnapshotService.shared
        snapshots.recordConditions(weather: results.0.flatMap { $0[primary.name] }, earthquakes: earthquakes)
        snapshots.recordIntelligence(alerts: alerts, weather: Array(savedWeather.values),
                                     earthquakes: earthquakes, news: newsByCategory)
        await announce(alerts)
    }

    /// Notifications and speech each remember what they have announced, so a repeat refresh is silent.
    private func announce(_ alerts: [IntelligenceAlert]) async {
        if defaults.bool(forKey: "intelligence.notificationsEnabled") {
            await notificationService.deliverNewCriticalAlerts(
                alerts,
                quietStartHour: defaults.object(forKey: "intelligence.quietStart") == nil ? 22 : defaults.integer(forKey: "intelligence.quietStart"),
                quietEndHour: defaults.object(forKey: "intelligence.quietEnd") == nil ? 7 : defaults.integer(forKey: "intelligence.quietEnd")
            )
        }
        SpeechService.shared.speakNewCriticalAlert(from: alerts)
    }

    /// The primary location first.
    private func savedLocations() -> [SavedLocationValue] {
        let locations = (try? context?.fetch(FetchDescriptor<SavedLocation>())) ?? []
        let values = locations
            .sorted { $0.isPrimary && !$1.isPrimary }
            .map { SavedLocationValue(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
        return values.isEmpty ? [Self.fallbackLocation] : values
    }

    /// One failed location does not discard the others; it throws only when every location fails.
    private func fetchWeather(for locations: [SavedLocationValue]) async throws -> [String: WeatherSnapshot] {
        let service = weatherService
        let results = await withTaskGroup(of: Result<WeatherSnapshot, Error>.self) { group in
            for location in locations {
                group.addTask { await capture { try await service.currentWeather(for: location) } }
            }
            var collected: [Result<WeatherSnapshot, Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }
        var output: [String: WeatherSnapshot] = [:]
        for case let .success(snapshot) in results { output[snapshot.locationName] = snapshot }
        if output.isEmpty, case let .failure(error)? = results.first { throw error }
        return output
    }

    private func fetchNews(category: NewsSource.Category) async throws -> [NewsArticle] {
        guard let source = NewsSource.defaults.first(where: { $0.category == category }) else { return [] }
        return try await newsService.articles(from: source)
    }

    private func fetchNewsAPI() async {
        let apiKey = await Task.detached(priority: .utility) { NewsAPIKeyStore().read() }.value
        guard let apiKey else {
            newsAPIArticles = [:]
            newsAPIMessage = nil
            return
        }
        newsAPIFetchedAt = .now
        // Results instead of try?, so a bad key or used-up quota is shown rather than silently ignored.
        let service = newsAPIService
        async let philippines = capture { try await service.articles(category: .philippines, apiKey: apiKey) }
        async let world = capture { try await service.articles(category: .world, apiKey: apiKey) }
        let results = await (philippines, world)
        if case let .success(articles) = results.0 { newsAPIArticles[.philippines] = articles }
        if case let .success(articles) = results.1 { newsAPIArticles[.world] = articles }
        newsAPIMessage = [results.0, results.1].compactMap { result -> String? in
            if case let .failure(error) = result { return error.localizedDescription }
            return nil
        }.first
    }
}

private func capture<T>(_ operation: () async throws -> T) async -> Result<T, Error> {
    do {
        return .success(try await operation())
    } catch {
        return .failure(error)
    }
}
