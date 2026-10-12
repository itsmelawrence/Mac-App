import CoreLocation
import MapKit
import SwiftData
import SwiftUI

/// A forecast-first companion to the geographic view. Selections are local to this Mac.
struct WeatherFocusDashboardView: View {
    let savedLocations: [SavedLocation]
    @Environment(\.modelContext) private var modelContext

    @AppStorage("weatherFocus.heroID") private var heroID = "primary"
    @AppStorage("weatherFocus.slot0") private var slot0 = "Baguio"
    @AppStorage("weatherFocus.slot1") private var slot1 = "Cebu"
    @AppStorage("weatherFocus.slot2") private var slot2 = "Davao"
    @AppStorage("weatherFocus.slot3") private var slot3 = "Iloilo"

    @State private var forecasts: [String: PhilippineLocationForecast] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var updatedAt: Date?
    @State private var showingCitySearch = false
    @State private var locationTarget = -1
    @State private var macLocation: SavedLocationValue?
    @StateObject private var locator = WeatherCurrentLocationProvider()

    private let service = PhilippineForecastService()

    private var choices: [SavedLocationValue] {
        let saved = savedLocations.map { SavedLocationValue(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
        var seen = Set<String>()
        return ((macLocation.map { [$0] } ?? []) + saved + PhilippineForecastService.locations)
            .filter { seen.insert($0.name.localizedLowercase).inserted }
    }

    private var primary: SavedLocationValue {
        let item = savedLocations.first(where: \.isPrimary) ?? savedLocations.first
        return item.map { SavedLocationValue(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
            ?? PhilippineForecastService.locations.first(where: { $0.name == "Manila" })!
    }

    private var heroLocation: SavedLocationValue {
        heroID == "primary" ? primary : choices.first(where: { $0.name == heroID }) ?? primary
    }

    private var slotNames: [String] { [slot0, slot1, slot2, slot3] }

    private var selectedLocations: [SavedLocationValue] {
        var seen = Set<String>()
        return ([heroLocation] + slotNames.compactMap { name in choices.first(where: { $0.name == name }) })
            .filter { seen.insert($0.id).inserted }
    }

    private var selectionKey: String { selectedLocations.map(\.id).joined(separator: "|") }

    var body: some View {
        DashboardSection(title: "My weather", systemImage: "sun.horizon.fill") {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Your primary location leads. Choose any saved or Philippine city for each view.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if let updatedAt {
                        Text("Updated \(updatedAt, style: .relative)").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { locationTarget = -1; showingCitySearch = true } label: {
                        Label("Find city", systemImage: "magnifyingglass")
                    }
                    Button {
                        locator.locate { result in
                            switch result {
                            case .success(let location):
                                macLocation = location
                                heroID = location.name
                                errorMessage = nil
                            case .failure:
                                errorMessage = "Mac location unavailable. Choose a city instead."
                            }
                        }
                    } label: { Label("Use Mac location", systemImage: "location") }
                    Button { Task { await refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(isLoading)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                heroCard
                HStack {
                    Text("OTHER LOCATIONS").font(.caption2.weight(.bold)).tracking(1.5).foregroundStyle(.secondary)
                    Spacer()
                    Text("Four independent forecasts").font(.caption).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in smallCard(at: index) }
                }
                Text("Hourly model forecasts from Open-Meteo, shown in each location’s local time. Conditions are estimates, not official warnings; consult PAGASA for Philippine alerts.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: selectionKey) { await refresh() }
        .sheet(isPresented: $showingCitySearch) {
            WeatherCitySearchView { location in
                let existing = savedLocations.first {
                    $0.name.localizedCaseInsensitiveCompare(location.name) == .orderedSame
                        && abs($0.latitude - location.latitude) < 0.01
                        && abs($0.longitude - location.longitude) < 0.01
                }
                if existing == nil {
                    modelContext.insert(SavedLocation(name: location.name, latitude: location.latitude,
                                                      longitude: location.longitude, isPrimary: false))
                    try? modelContext.save()
                }
                if locationTarget < 0 { heroID = location.name }
                else { setSlot(locationTarget, to: location.name) }
            }
        }
    }

    private var heroCard: some View {
        let forecast = forecasts[heroLocation.id]
        let hour = forecast?.hour(closestTo: .now)
        let condition = WeatherPointCondition(code: hour?.weatherCode, precipitation: hour?.precipitation)
        return VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("CURRENT CONDITIONS").font(.caption2.weight(.bold)).tracking(1.8).foregroundStyle(.white.opacity(0.72))
                    locationMenu(title: heroLocation.name, includesPrimary: true,
                                 find: { locationTarget = -1; showingCitySearch = true }) { heroID = $0 }
                        .font(.title2.weight(.semibold))
                    Text(hour?.temperature.map { "\(Int($0.rounded()))°" } ?? "—°")
                        .font(.system(size: 76, weight: .light, design: .rounded)).monospacedDigit()
                    Text(condition.title).font(.title3.weight(.medium))
                }
                Spacer(minLength: 12)
                AnimatedWeatherGlyph(condition: condition, size: 92)
                    .frame(width: 120, height: 110)
            }
            HStack(spacing: 22) {
                metric("RAIN", hour?.rainChance.map { "\($0)%" } ?? "—", symbol: "drop.fill")
                metric("WIND", hour?.windSpeed.map { "\(Int($0.rounded())) km/h" } ?? "—", symbol: "wind")
                metric("HUMIDITY", hour?.humidity.map { "\($0)%" } ?? "—", symbol: "humidity.fill")
                Spacer(minLength: 0)
            }
            Divider().overlay(.white.opacity(0.25))
            if let forecast {
                hourlyStrip(forecast)
            } else if isLoading {
                ProgressView("Loading forecast…").tint(.white)
            } else {
                Text("No forecast available for this location yet.").font(.caption).foregroundStyle(.white.opacity(0.75))
            }
        }
        .foregroundStyle(.white)
        .padding(25)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: heroGradient(condition), startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12)))
    }

    private func metric(_ label: String, _ value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.66))
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }

    private func hourlyStrip(_ forecast: PhilippineLocationForecast) -> some View {
        let hours = Array(forecast.hours.filter { $0.time >= .now.addingTimeInterval(-1800) }.prefix(6))
        return HStack(spacing: 12) {
            ForEach(hours, id: \.time) { hour in
                VStack(spacing: 7) {
                    Text(formattedTime(hour.time, for: forecast, format: "h a"))
                        .font(.caption2).foregroundStyle(.white.opacity(0.75))
                    Image(systemName: WeatherPointCondition(code: hour.weatherCode, precipitation: hour.precipitation).systemImage)
                        .symbolRenderingMode(.multicolor).font(.system(size: 19))
                    Text(hour.temperature.map { "\(Int($0.rounded()))°" } ?? "—")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func smallCard(at index: Int) -> some View {
        let name = slotNames[index]
        let location = choices.first(where: { $0.name == name })
        let forecast = location.flatMap { forecasts[$0.id] }
        let hour = forecast?.hour(closestTo: .now)
        let condition = WeatherPointCondition(code: hour?.weatherCode, precipitation: hour?.precipitation)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                locationMenu(title: location?.name ?? name, includesPrimary: false,
                             find: { locationTarget = index; showingCitySearch = true }) { setSlot(index, to: $0) }
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                AnimatedWeatherGlyph(condition: condition, size: 42)
                    .frame(width: 50, height: 45)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(hour?.temperature.map { "\(Int($0.rounded()))°" } ?? "—°")
                    .font(.system(size: 42, weight: .light, design: .rounded)).monospacedDigit()
                Spacer(minLength: 2)
                Text(condition.title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Divider()
            HStack {
                Label(hour?.rainChance.map { "\($0)% rain" } ?? "Rain —", systemImage: "drop")
                Spacer()
                Text(forecast.map { localTime(for: $0) } ?? "Awaiting data")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .leading)
        .background(Color(red: 0.055, green: 0.11, blue: 0.17), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.cyan.opacity(0.16)))
    }

    private func locationMenu(title: String, includesPrimary: Bool, find: @escaping () -> Void,
                              select: @escaping (String) -> Void) -> some View {
        Menu {
            if includesPrimary {
                Button("Follow primary · \(primary.name)") { select("primary") }
                Divider()
            }
            ForEach(choices) { location in
                Button(location.name) { select(location.name) }
            }
            Divider()
            Button("Find another city…", systemImage: "magnifyingglass", action: find)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin")
                Text(title).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("Choose location for \(title)")
    }

    private func setSlot(_ index: Int, to name: String) {
        switch index {
        case 0: slot0 = name
        case 1: slot1 = name
        case 2: slot2 = name
        default: slot3 = name
        }
    }

    private func localTime(for forecast: PhilippineLocationForecast) -> String {
        formattedTime(.now, for: forecast, format: "h:mm a")
    }

    private func formattedTime(_ date: Date, for forecast: PhilippineLocationForecast, format: String) -> String {
        let zone = TimeZone(identifier: forecast.timeZoneIdentifier) ?? .current
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private func heroGradient(_ condition: WeatherPointCondition) -> [Color] {
        switch condition {
        case .clear, .partlyCloudy: [Color(red: 0.08, green: 0.37, blue: 0.63), Color(red: 0.02, green: 0.12, blue: 0.25)]
        case .thunderstorm, .heavyRain: [Color(red: 0.15, green: 0.18, blue: 0.35), Color(red: 0.02, green: 0.07, blue: 0.17)]
        default: [Color(red: 0.10, green: 0.28, blue: 0.43), Color(red: 0.03, green: 0.10, blue: 0.20)]
        }
    }

    @MainActor
    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.forecast(for: selectedLocations)
            for item in result { forecasts[item.id] = item }
            updatedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = forecasts.isEmpty ? "Forecast unavailable. Try Refresh." : "Refresh failed; showing the last forecast."
        }
    }
}

private struct WeatherCitySearchView: View {
    let onSelect: (SavedLocationValue) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Search a city or town", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
                if isSearching { ProgressView("Finding locations…") }
                if let errorMessage { Text(errorMessage).foregroundStyle(.orange).font(.caption) }
                List(Array(results.enumerated()), id: \.offset) { _, item in
                    Button {
                        let place = item.placemark
                        let name = place.locality ?? item.name ?? query
                        let displayName = [name, place.administrativeArea].compactMap { $0 }.joined(separator: ", ")
                        onSelect(SavedLocationValue(name: displayName, latitude: place.coordinate.latitude,
                                                    longitude: place.coordinate.longitude))
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Location")
                            Text([item.placemark.locality, item.placemark.administrativeArea, item.placemark.country]
                                .compactMap { $0 }.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .navigationTitle("Find a weather location")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .frame(width: 510, height: 430)
    }

    @MainActor
    private func search() async {
        isSearching = true
        defer { isSearching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        request.resultTypes = .address
        do {
            results = try await MKLocalSearch(request: request).start().mapItems
            errorMessage = results.isEmpty ? "No cities found. Try a more specific name." : nil
        } catch {
            errorMessage = "Location search is unavailable. Check your connection and try again."
        }
    }
}

@MainActor
private final class WeatherCurrentLocationProvider: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<SavedLocationValue, Error>) -> Void)?

    func locate(_ completion: @escaping (Result<SavedLocationValue, Error>) -> Void) {
        self.completion = completion
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: completion(.failure(CLError(.denied)))
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: completion?(.failure(CLError(.denied))); completion = nil
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            Task { @MainActor in
                let city = placemarks?.first?.locality ?? "Your location"
                self?.completion?(.success(SavedLocationValue(name: "Mac location · \(city)",
                    latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)))
                self?.completion = nil
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        completion?(.failure(error))
        completion = nil
    }
}

/// Motion is decorative only; reduced-motion users get the same condition icon without animation.
struct AnimatedWeatherGlyph: View {
    let condition: WeatherPointCondition
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 12, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            let drift = reduceMotion ? 0 : sin(phase * 1.5) * 2
            let pulse = reduceMotion ? 1 : 1 + sin(phase * 1.8) * 0.035
            Image(systemName: condition.systemImage)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: size, weight: .regular))
                .scaleEffect(pulse)
                .offset(x: condition == .clear ? 0 : drift)
                .shadow(color: condition == .thunderstorm ? .yellow.opacity(0.4) : .cyan.opacity(0.25), radius: 12)
        }
        .accessibilityLabel(condition.title)
    }
}
