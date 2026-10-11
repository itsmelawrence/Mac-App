import AppKit
import MapKit
import SwiftUI

private enum WeatherMapLabelSize {
    static func measure(_ text: String) -> CGSize {
        let textSize = (text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ])
        return CGSize(width: ceil(textSize.width) + 18, height: ceil(textSize.height) + 10)
    }
}

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

    func label(_ hour: PhilippineForecastHour?) -> String {
        guard let hour else { return "—" }
        return label(hour)
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

private func rainBandColor(_ band: WeatherRainBand) -> Color {
    switch band {
    case .low: Color(red: 0.37, green: 0.91, blue: 1)
    case .moderate: Color(red: 0.29, green: 0.64, blue: 1)
    case .high: Color(red: 0.65, green: 0.55, blue: 1)
    case .extreme: Color(red: 0.94, green: 0.42, blue: 0.91)
    case .thunderstorm: Color(red: 0.96, green: 0.73, blue: 0.29)
    case .unavailable: .gray
    }
}

private struct WeatherBeacon: View {
    let name: String
    let hour: PhilippineForecastHour?
    let isSelected: Bool
    let isHovered: Bool
    let labelSide: WeatherLabelSide?
    let labelText: String
    let action: () -> Void
    let hovering: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var condition: WeatherPointCondition {
        WeatherPointCondition(code: hour?.weatherCode, precipitation: hour?.precipitation)
    }

    private var band: WeatherRainBand {
        WeatherRainBand(chance: hour?.rainChance, thunderstorm: condition.isThunderstorm)
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Circle().stroke(Color.cyan.opacity(0.65), lineWidth: 2)
                        .frame(width: 44, height: 44)
                }
                Circle()
                    .fill(Color(red: 0.03, green: 0.07, blue: 0.12).opacity(0.92))
                    .frame(width: 38, height: 38)
                if let chance = hour?.rainChance {
                    Circle()
                        .trim(from: 0, to: min(1, max(0, CGFloat(chance) / 100)))
                        .stroke(rainBandColor(band), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 36, height: 36)
                } else {
                    Circle()
                        .stroke(.gray, style: StrokeStyle(lineWidth: 2.5, dash: [3, 3]))
                        .frame(width: 36, height: 36)
                }
                Image(systemName: condition.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(condition.isThunderstorm ? Color.orange : Color(red: 0.91, green: 0.95, blue: 0.98))
                    .symbolRenderingMode(.hierarchical)
            }
            .frame(width: 44, height: 44)
            .scaleEffect(isHovered ? 1.08 : 1)
            .shadow(color: .black.opacity(0.5), radius: 5)
        }
        .buttonStyle(.plain)
        .overlay {
            if let labelSide {
                let labelSize = WeatherMapLabelSize.measure(labelText)
                let rect = labelSide.rect(around: .zero, labelSize: labelSize)
                Text(labelText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .fixedSize()
                    .foregroundStyle(Color(red: 0.91, green: 0.95, blue: 0.98))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(red: 0.03, green: 0.07, blue: 0.11).opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(Color(red: 0.12, green: 0.2, blue: 0.28)))
                    .offset(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: labelSide)
        .onHover(perform: hovering)
        .accessibilityLabel("\(name): \(condition.title), \(hour?.rainChance.map { "\($0)% chance of rain" } ?? "rain chance unavailable")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
    @State private var hoveredLocationID: String?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var labelSides: [String: WeatherLabelSide] = [:]
    @State private var lastLabelSpan: CLLocationDegrees?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedAt: Date?
    @AppStorage("weatherMap.allLabels") private var allLabels = false

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
                    Picker("Detail metric", selection: $layer) {
                        ForEach(WeatherMapLayer.allCases) { layer in
                            Label(layer.rawValue, systemImage: layer.symbol).tag(layer)
                        }
                    }
                    .frame(width: 220)
                    Toggle("More labels", isOn: $allLabels)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Button { cameraPosition = .rect(Self.fittedRect(for: forecasts)) } label: {
                        Label("Reset view", systemImage: "scope")
                    }
                    .disabled(forecasts.isEmpty)
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
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            map.frame(minWidth: 440, maxWidth: .infinity).frame(height: 720)
                            locationDetail.frame(width: 400, height: 720)
                        }
                        VStack(spacing: 14) {
                            map.frame(height: 680)
                            locationDetail.frame(height: 620)
                        }
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
        return MapReader { proxy in
            GeometryReader { geometry in
                Map(position: $cameraPosition, bounds: MapCameraBounds(
                    centerCoordinateBounds: MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 11.9, longitude: 122),
                        span: MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 18)
                    ),
                    minimumDistance: 70_000,
                    maximumDistance: 2_700_000
                )) {
                    ForEach(forecasts) { forecast in
                        Annotation("", coordinate: CLLocationCoordinate2D(
                            latitude: forecast.location.latitude,
                            longitude: forecast.location.longitude
                        )) {
                            let hour = forecast.hours.indices.contains(selectedTimeIndex)
                                ? forecast.hours[selectedTimeIndex] : nil
                            WeatherBeacon(
                                name: forecast.location.name,
                                hour: hour,
                                isSelected: selectedForecast?.id == forecast.id,
                                isHovered: hoveredLocationID == forecast.id,
                                labelSide: labelSides[forecast.id],
                                labelText: "\(forecast.location.name) · \(layer.label(hour))",
                                action: { selectedLocationID = forecast.id },
                                hovering: { hoveredLocationID = $0 ? forecast.id : nil }
                            )
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .onMapCameraChange(frequency: .continuous) { context in
                    let span = context.region.span.latitudeDelta
                    if let previous = lastLabelSpan, previous > 0,
                       abs(span - previous) / previous > 0.04 {
                        lastLabelSpan = span
                        updateLabelSides(proxy: proxy, size: geometry.size)
                    } else if lastLabelSpan == nil {
                        lastLabelSpan = span
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    lastLabelSpan = context.region.span.latitudeDelta
                    updateLabelSides(proxy: proxy, size: geometry.size)
                }
                .onAppear { updateLabelSides(proxy: proxy, size: geometry.size) }
                .onChange(of: geometry.size) { _, size in updateLabelSides(proxy: proxy, size: size) }
                .onChange(of: loadedAt) { _, _ in updateLabelSides(proxy: proxy, size: geometry.size) }
                .onChange(of: selectedTimeIndex) { _, _ in updateLabelSides(proxy: proxy, size: geometry.size) }
                .onChange(of: selectedLocationID) { _, _ in updateLabelSides(proxy: proxy, size: geometry.size) }
                .onChange(of: hoveredLocationID) { _, _ in updateLabelSides(proxy: proxy, size: geometry.size) }
                .onChange(of: allLabels) { _, _ in updateLabelSides(proxy: proxy, size: geometry.size) }
                .onChange(of: layer) { _, _ in updateLabelSides(proxy: proxy, size: geometry.size) }
                .overlay(alignment: .bottomLeading) {
                    Text("16 forecast points · Open-Meteo · Asia/Manila · \(loadedAt.map { formattedTime($0, format: "h:mm a") } ?? "awaiting data")")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(9)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
    }

    private func updateLabelSides(proxy: MapProxy, size: CGSize) {
        let points = forecasts.map { forecast -> WeatherLabelPoint in
            let hour = forecast.hours.indices.contains(selectedTimeIndex)
                ? forecast.hours[selectedTimeIndex] : nil
            let condition = WeatherPointCondition(code: hour?.weatherCode, precipitation: hour?.precipitation)
            let focus = forecast.id == selectedForecast?.id || forecast.id == hoveredLocationID
            let title = "\(forecast.location.name) · \(layer.label(hour))"
            return WeatherLabelPoint(
                id: forecast.id,
                position: proxy.convert(CLLocationCoordinate2D(
                    latitude: forecast.location.latitude,
                    longitude: forecast.location.longitude
                ), to: .local),
                labelSize: WeatherMapLabelSize.measure(title),
                priority: (condition.isThunderstorm ? 1_000 : 0) + (hour?.rainChance ?? -1),
                isFocused: focus
            )
        }
        let next = WeatherLabelPlacer.place(
            points: points, viewSize: size, maxLabels: allLabels ? 16 : 6, previous: labelSides
        )
        if next != labelSides { labelSides = next }
    }

    private static func fittedRect(for forecasts: [PhilippineLocationForecast]) -> MKMapRect {
        let locations = forecasts.isEmpty ? PhilippineForecastService.locations : forecasts.map(\.location)
        let points = locations.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        guard let first = points.first else { return MKMapRect.world }
        let minX = points.map(\.x).min() ?? first.x
        let maxX = points.map(\.x).max() ?? first.x
        let minY = points.map(\.y).min() ?? first.y
        let maxY = points.map(\.y).max() ?? first.y
        let width = maxX - minX
        let height = maxY - minY
        // The northernmost beacon needs room for its ring and label above the coordinate.
        return MKMapRect(x: minX - width * 0.14, y: minY - height * 0.35,
                         width: width * 1.28, height: height * 1.50)
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
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            if let forecast = selectedForecast,
               forecast.hours.indices.contains(selectedTimeIndex) {
                let hour = forecast.hours[selectedTimeIndex]
                let condition = WeatherPointCondition(code: hour.weatherCode, precipitation: hour.precipitation)
                Text("SELECTED FORECAST POINT")
                    .font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(.secondary)
                Text(forecast.location.name).font(.title2.weight(.bold))
                Text(selectedTime.map { formattedTime($0, format: "EEE, MMM d · h:mm a") } ?? "Time unavailable")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Image(systemName: condition.systemImage)
                        .font(.system(size: 38))
                        .foregroundStyle(condition.isThunderstorm ? Color.orange : Color.cyan)
                        .frame(width: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hour.temperature.map { "\(Int($0.rounded()))°C" } ?? "—")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text(condition.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text("\(layer.rawValue): \(layer.label(hour))")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(layer.tint(hour))
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
            Divider()
            Text("WETTEST AT THIS TIME")
                .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
            ForEach(wettestForecasts.prefix(6)) { forecast in
                Button { selectedLocationID = forecast.id } label: {
                    let hour = forecast.hours.indices.contains(selectedTimeIndex) ? forecast.hours[selectedTimeIndex] : nil
                    let condition = WeatherPointCondition(code: hour?.weatherCode, precipitation: hour?.precipitation)
                    HStack(spacing: 8) {
                        Image(systemName: condition.systemImage).frame(width: 20)
                            .foregroundStyle(condition.isThunderstorm ? Color.orange : Color.cyan)
                        Text(forecast.location.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(hour?.rainChance.map { "\($0)%" } ?? "—")
                            .monospacedDigit().foregroundStyle(rainBandColor(WeatherRainBand(
                                chance: hour?.rainChance,
                                thunderstorm: condition.isThunderstorm
                            )))
                    }
                    .font(.caption).frame(minHeight: 32)
                }
                .buttonStyle(.plain)
            }
            Divider()
            rainLegend
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var wettestForecasts: [PhilippineLocationForecast] {
        forecasts.sorted { left, right in
            let a = left.hours.indices.contains(selectedTimeIndex) ? left.hours[selectedTimeIndex] : nil
            let b = right.hours.indices.contains(selectedTimeIndex) ? right.hours[selectedTimeIndex] : nil
            return (a?.rainChance ?? -1) > (b?.rainChance ?? -1)
        }
    }

    private var rainLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RAIN-CHANCE RING")
                .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
            ForEach([WeatherRainBand.low, .moderate, .high, .extreme, .thunderstorm], id: \.self) { band in
                HStack(spacing: 7) {
                    Circle().fill(rainBandColor(band)).frame(width: 9, height: 9)
                    Text(band.label).font(.caption)
                }
            }
            Text("Each ring describes one forecast point; it does not show rain coverage between points. Check PAGASA for official warnings.")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            let firstLoad = forecasts.isEmpty
            forecasts = result
            if firstLoad { cameraPosition = .rect(Self.fittedRect(for: result)) }
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
