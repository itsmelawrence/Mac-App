import MapKit
import SwiftUI

private enum WeatherMapLayer: String, CaseIterable, Identifiable {
    case temperature = "Temperature"
    case rainChance = "Rain chance"
    case rainfall = "Rainfall"
    case wind = "Wind"
    case clouds = "Clouds"
    case humidity = "Humidity"
    case pressure = "Pressure"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .rainChance, .rainfall: "cloud.rain.fill"
        case .wind: "wind"
        case .clouds: "cloud.fill"
        case .humidity: "humidity.fill"
        case .pressure: "gauge.with.dots.needle.33percent"
        }
    }

    func value(_ hour: PhilippineForecastHour) -> Double? {
        switch self {
        case .temperature: hour.temperature
        case .rainChance: hour.rainChance.map(Double.init)
        case .rainfall: hour.precipitation
        case .wind: hour.windSpeed
        case .clouds: hour.cloudCover.map(Double.init)
        case .humidity: hour.humidity.map(Double.init)
        case .pressure: hour.pressure
        }
    }

    func label(_ hour: PhilippineForecastHour) -> String {
        guard let value = value(hour) else { return "—" }
        switch self {
        case .temperature: return "\(Int(value.rounded()))°C"
        case .rainChance, .clouds, .humidity: return "\(Int(value.rounded()))%"
        case .rainfall: return String(format: "%.1f mm", value)
        case .wind: return "\(Int(value.rounded())) km/h"
        case .pressure: return "\(Int(value.rounded())) hPa"
        }
    }

    func tint(_ hour: PhilippineForecastHour) -> Color {
        guard let value = value(hour) else { return .gray }
        switch self {
        case .temperature:
            return value >= 34 ? .red : value >= 29 ? .orange : value >= 24 ? .yellow : .cyan
        case .rainChance:
            return value >= 75 ? .purple : value >= 50 ? .blue : value >= 25 ? .cyan : .green
        case .rainfall:
            return value >= 10 ? .purple : value >= 2.5 ? .blue : value > 0 ? .cyan : .green
        case .wind:
            return value >= 60 ? .red : value >= 35 ? .orange : value >= 15 ? .yellow : .green
        case .clouds, .humidity:
            return value >= 75 ? .indigo : value >= 45 ? .blue : .cyan
        case .pressure:
            return value < 995 ? .red : value < 1005 ? .orange : .cyan
        }
    }
}

struct PhilippineWeatherMapView: View {
    private enum DetailMode: String, CaseIterable {
        case hourly = "Hourly"
        case daily = "7 days"
    }

    @State private var forecasts: [PhilippineLocationForecast] = []
    @State private var layer: WeatherMapLayer = .rainChance
    @State private var detailMode: DetailMode = .hourly
    @State private var selectedTimeIndex = 0
    @State private var selectedLocationID: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedAt: Date?

    private let service = PhilippineForecastService()
    private let timeZone = TimeZone(identifier: "Asia/Manila")!

    private var timeline: [Date] { forecasts.first?.hours.map(\.time) ?? [] }
    private var selectedTime: Date? { timeline.indices.contains(selectedTimeIndex) ? timeline[selectedTimeIndex] : nil }
    private var selectedForecast: PhilippineLocationForecast? {
        forecasts.first { $0.id == selectedLocationID } ?? forecasts.first
    }

    var body: some View {
        DashboardSection(title: "Philippines weather map", systemImage: "map.fill") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Picker("Layer", selection: $layer) {
                        ForEach(WeatherMapLayer.allCases) { layer in
                            Label(layer.rawValue, systemImage: layer.symbol).tag(layer)
                        }
                    }
                    .frame(width: 220)
                    Spacer()
                    if let loadedAt {
                        Text("Updated \(loadedAt, style: .relative)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button { Task { await refresh() } } label: {
                        Label("Refresh map", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                if forecasts.isEmpty {
                    if isLoading {
                        ProgressView("Loading the Philippine forecast…")
                            .frame(maxWidth: .infinity, minHeight: 380)
                    } else {
                        ContentUnavailableView("Forecast unavailable", systemImage: "cloud.slash", description: Text("Refresh the map to try again."))
                            .frame(height: 380)
                    }
                } else {
                    HStack(alignment: .top, spacing: 14) {
                        map.frame(maxWidth: .infinity, minHeight: 480)
                        locationDetail.frame(width: 280)
                    }
                    timelineControls
                }

                Text("Forecast samples at 16 Philippine locations, not a continuous weather raster or live radar. Times are Philippine time. Data: Open-Meteo; check PAGASA for official warnings.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task { if forecasts.isEmpty { await refresh() } }
    }

    private var map: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 12.5, longitude: 122.8),
            span: MKCoordinateSpan(latitudeDelta: 18.5, longitudeDelta: 15.0)
        ))) {
            ForEach(forecasts) { forecast in
                Annotation("", coordinate: CLLocationCoordinate2D(
                    latitude: forecast.location.latitude,
                    longitude: forecast.location.longitude
                )) {
                    Button { selectedLocationID = forecast.id } label: {
                        let hour = forecast.hours.indices.contains(selectedTimeIndex)
                            ? forecast.hours[selectedTimeIndex] : nil
                        VStack(spacing: 2) {
                            Text(hour.map { layer.label($0) } ?? "—")
                                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                            Text(forecast.location.name).font(.system(size: 9, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(hour.map { layer.tint($0) } ?? .gray, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(selectedForecast?.id == forecast.id ? .white : .clear, lineWidth: 2))
                        .shadow(color: .black.opacity(0.35), radius: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
    }

    private var timelineControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(selectedTime.map { formattedTime($0, format: "EEE, MMM d · h:mm a") } ?? "Forecast time", systemImage: "clock")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("7-day hourly forecast").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button { selectedTimeIndex = max(0, selectedTimeIndex - 1) } label: { Image(systemName: "chevron.left") }
                    .disabled(selectedTimeIndex == 0)
                Slider(value: Binding(
                    get: { Double(selectedTimeIndex) },
                    set: { selectedTimeIndex = Int($0.rounded()) }
                ), in: 0...Double(max(1, timeline.count - 1)), step: 1)
                Button { selectedTimeIndex = min(timeline.count - 1, selectedTimeIndex + 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(selectedTimeIndex >= timeline.count - 1)
            }
        }
    }

    private var locationDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let forecast = selectedForecast,
               forecast.hours.indices.contains(selectedTimeIndex) {
                let hour = forecast.hours[selectedTimeIndex]
                Text(forecast.location.name).font(.headline)
                Text(layer.label(hour)).font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(layer.tint(hour))
                Divider()
                detailLine("Temperature", hour.temperature.map { "\(Int($0.rounded()))°C" })
                detailLine("Rain chance", hour.rainChance.map { "\($0)%" })
                detailLine("Rainfall", hour.precipitation.map { String(format: "%.1f mm", $0) })
                detailLine("Wind", hour.windSpeed.map { "\(Int($0.rounded())) km/h" })
                detailLine("Wind direction", hour.windDirection.map { "\(Int($0.rounded()))°" })
                detailLine("Cloud cover", hour.cloudCover.map { "\($0)%" })
                detailLine("Humidity", hour.humidity.map { "\($0)%" })
                detailLine("Pressure", hour.pressure.map { "\(Int($0.rounded())) hPa" })
                Divider()
                Picker("Forecast detail", selection: $detailMode) {
                    ForEach(DetailMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.segmented).labelsHidden()
                ScrollView {
                    if detailMode == .hourly {
                        VStack(spacing: 7) {
                            ForEach(Array(forecast.hours.dropFirst(selectedTimeIndex).prefix(24)), id: \.time) { future in
                                HStack {
                                    Text(formattedTime(future.time, format: "EEE h a"))
                                    Spacer()
                                    Text(future.temperature.map { "\(Int($0.rounded()))°" } ?? "—")
                                    Text(future.rainChance.map { "\($0)%" } ?? "—")
                                        .foregroundStyle(.cyan)
                                }
                                .font(.caption).monospacedDigit()
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(dailySummaries(for: forecast), id: \.day) { summary in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formattedTime(summary.day, format: "EEE, MMM d"))
                                        .font(.caption.weight(.semibold))
                                    Text("\(summary.low)–\(summary.high)°C · \(summary.rainChance)% rain")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(String(format: "%.1f mm total · wind up to %d km/h", summary.rainfall, summary.wind))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 480, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailLine(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—").monospacedDigit()
        }
        .font(.caption)
    }

    private func formattedTime(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private struct DaySummary {
        let day: Date
        let low: Int
        let high: Int
        let rainChance: Int
        let rainfall: Double
        let wind: Int
    }

    private func dailySummaries(for forecast: PhilippineLocationForecast) -> [DaySummary] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let groups = Dictionary(grouping: forecast.hours) { calendar.startOfDay(for: $0.time) }
        return groups.keys.sorted().compactMap { day in
            guard let hours = groups[day], !hours.isEmpty else { return nil }
            let temperatures = hours.compactMap(\.temperature)
            return DaySummary(
                day: day,
                low: Int((temperatures.min() ?? 0).rounded()),
                high: Int((temperatures.max() ?? 0).rounded()),
                rainChance: hours.compactMap(\.rainChance).max() ?? 0,
                rainfall: hours.compactMap(\.precipitation).reduce(0, +),
                wind: Int((hours.compactMap(\.windSpeed).max() ?? 0).rounded())
            )
        }
    }

    @MainActor
    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await service.forecast()
            guard result.contains(where: { !$0.hours.isEmpty }) else { throw URLError(.cannotParseResponse) }
            forecasts = result
            selectedTimeIndex = result.first?.hours.firstIndex(where: { $0.time >= .now }) ?? 0
            selectedLocationID = selectedLocationID ?? result.first?.id
            loadedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = forecasts.isEmpty
                ? "The forecast service did not respond."
                : "Refresh failed; showing the previous forecast."
        }
    }
}
