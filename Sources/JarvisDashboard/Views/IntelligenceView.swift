import SwiftData
import SwiftUI

struct IntelligenceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var savedLocations: [SavedLocation]

    @State private var savedWeather: [String: WeatherSnapshot] = [:]
    @State private var regionalWeather: [String: WeatherSnapshot] = [:]
    @State private var earthquakes: [EarthquakeEvent] = []
    @State private var news: [NewsArticle] = []
    @State private var newsCategory = NewsSource.Category.philippines
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingLocationPicker = false

    private let weatherService = OpenMeteoWeatherService()
    private let earthquakeService = USGSEarthquakeService()
    private let newsService = RSSNewsService()
    private let newsAPIService = NewsAPIService()
    private let newsAPIKeyStore = NewsAPIKeyStore()

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }

                savedLocationsSection
                regionalForecastSection
                earthquakeSection
                newsSection
            }
            .padding(28)
        }
        .navigationTitle("Intelligence")
        .toolbar {
            Button { showingLocationPicker = true } label: {
                Label("Add location", systemImage: "plus")
            }
            Button { Task { await refresh() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
        .sheet(isPresented: $showingLocationPicker) {
            AddLocationView(existingNames: Set(savedLocations.map(\.name))) { preset in
                if preset.makePrimary {
                    savedLocations.forEach { $0.isPrimary = false }
                }
                modelContext.insert(
                    SavedLocation(
                        name: preset.location.name,
                        latitude: preset.location.latitude,
                        longitude: preset.location.longitude,
                        isPrimary: preset.makePrimary
                    )
                )
                Task { await refresh() }
            }
        }
        .task {
            seedDefaultLocationIfNeeded()
            await refresh()
        }
        .onChange(of: newsCategory) { _, _ in
            Task { await refreshNews() }
        }
    }

    private var savedLocationsSection: some View {
        DashboardSection(title: "Saved locations", systemImage: "location.fill") {
            if savedLocations.isEmpty {
                ContentUnavailableView(
                    "No saved locations",
                    systemImage: "location.slash",
                    description: Text("Add a location for its current conditions.")
                )
                .frame(height: 160)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(savedLocations) { location in
                        SavedWeatherCard(
                            location: location,
                            weather: savedWeather[location.name],
                            makePrimary: {
                                savedLocations.forEach { $0.isPrimary = $0.persistentModelID == location.persistentModelID }
                            },
                            delete: { modelContext.delete(location) }
                        )
                    }
                }
            }
        }
    }

    private var regionalForecastSection: some View {
        DashboardSection(title: "Philippines weather overview", systemImage: "map.fill") {
            Text("Representative conditions across Luzon, Visayas, and Mindanao")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(regionalLocations) { location in
                    let weather = regionalWeather[location.name]
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(location.name).font(.headline)
                            Spacer()
                            Image(systemName: weather?.systemImage ?? "cloud")
                                .foregroundStyle(.cyan)
                        }
                        if let weather {
                            Text("\(Int(weather.temperature.rounded()))°C")
                                .font(.title2.bold().monospacedDigit())
                            Text(weather.condition)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(13)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("Weather data: Open-Meteo. Consult PAGASA for official Philippine warnings and bulletins.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var earthquakeSection: some View {
        DashboardSection(title: "Philippine-region earthquakes", systemImage: "waveform.path.ecg") {
            if earthquakes.isEmpty && isLoading {
                ProgressView().controlSize(.small)
            } else if earthquakes.isEmpty {
                Text("No events were reported by the current feed in the past 24 hours.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(earthquakes.prefix(15)) { event in
                        HStack(spacing: 14) {
                            Text("M\(event.magnitude, specifier: "%.1f")")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(event.magnitude >= 5 ? .orange : .primary)
                                .frame(width: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.place)
                                Text(event.occurredAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let url = event.detailURL {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .help("Open USGS event details")
                            }
                        }
                        .padding(.vertical, 9)
                        if event.id != earthquakes.prefix(15).last?.id { Divider() }
                    }
                }
            }
            Text("Preliminary earthquake data: USGS. Critical decisions should be confirmed with PHIVOLCS.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var newsSection: some View {
        DashboardSection(title: "News briefing", systemImage: "newspaper") {
            Picker("News region", selection: $newsCategory) {
                ForEach(NewsSource.Category.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if news.isEmpty && isLoading {
                ProgressView().controlSize(.small)
            } else if news.isEmpty {
                ContentUnavailableView(
                    "News unavailable",
                    systemImage: "newspaper",
                    description: Text("The selected RSS source did not return any stories.")
                )
                .frame(height: 160)
            } else {
                VStack(spacing: 0) {
                    ForEach(news.prefix(12)) { article in
                        Link(destination: article.link) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(article.title)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    HStack {
                                        Text(article.sourceName)
                                        if let publishedAt = article.publishedAt {
                                            Text("·")
                                            Text(publishedAt, style: .relative)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        if article.id != news.prefix(12).last?.id { Divider() }
                    }
                }
            }
        }
    }

    private func seedDefaultLocationIfNeeded() {
        guard savedLocations.isEmpty else { return }
        modelContext.insert(SavedLocation(name: "Manila", latitude: 14.5995, longitude: 120.9842, isPrimary: true))
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }

        let savedLocationValues = savedLocations.isEmpty
            ? [SavedLocationValue(name: "Manila", latitude: 14.5995, longitude: 120.9842)]
            : savedLocations.map {
                SavedLocationValue(name: $0.name, latitude: $0.latitude, longitude: $0.longitude)
            }
        async let savedRequest = try? fetchWeather(for: savedLocationValues)
        async let regionalRequest = try? fetchWeather(for: regionalLocations)
        async let earthquakeRequest = try? earthquakeService.recentPhilippineEvents()
        async let newsRequest = try? fetchNews(category: newsCategory)

        let results = await (savedRequest, regionalRequest, earthquakeRequest, newsRequest)
        if let result = results.0 { savedWeather = result }
        if let result = results.1 { regionalWeather = result }
        if let result = results.2 { earthquakes = result }
        if let result = results.3 { news = result }

        errorMessage = [results.0 != nil, results.1 != nil, results.2 != nil, results.3 != nil].allSatisfy { $0 }
            ? nil
            : "One or more live sources could not be refreshed. Available results remain visible."
    }

    @MainActor
    private func refreshNews() async {
        do {
            news = try await fetchNews(category: newsCategory)
        } catch {
            errorMessage = "The selected news source could not be refreshed."
        }
    }

    private func fetchWeather(for locations: [SavedLocationValue]) async throws -> [String: WeatherSnapshot] {
        try await withThrowingTaskGroup(of: WeatherSnapshot.self) { group in
            for location in locations {
                group.addTask { try await weatherService.currentWeather(for: location) }
            }
            var output: [String: WeatherSnapshot] = [:]
            for try await snapshot in group { output[snapshot.locationName] = snapshot }
            return output
        }
    }

    private func fetchNews(category: NewsSource.Category) async throws -> [NewsArticle] {
        guard let source = NewsSource.defaults.first(where: { $0.category == category }) else { return [] }
        if let apiKey = newsAPIKeyStore.read() {
            do {
                let articles = try await newsAPIService.articles(category: category, apiKey: apiKey)
                if !articles.isEmpty { return articles }
            } catch {
                // Preserve the dashboard when a key expires or a plan limit is reached.
            }
        }
        return try await newsService.articles(from: source)
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
