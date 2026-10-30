import AppKit
import MapKit
import SwiftUI

/// The value the map's chips show and colour by.
enum WeatherMapMetric: String, CaseIterable, Identifiable {
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
        case .rainChance: "cloud.rain.fill"
        case .rainfall: "drop.fill"
        case .wind: "wind"
        case .clouds: "cloud.fill"
        case .humidity: "humidity.fill"
        case .pressure: "gauge.with.dots.needle.33percent"
        }
    }

    func value(_ hour: PhilippineForecastHour?) -> Double? {
        guard let hour else { return nil }
        switch self {
        case .temperature: return hour.temperature
        case .rainChance: return hour.rainChance.map(Double.init)
        case .rainfall: return hour.precipitation
        case .wind: return hour.windSpeed
        case .clouds: return hour.cloudCover.map(Double.init)
        case .humidity: return hour.humidity.map(Double.init)
        case .pressure: return hour.pressure
        }
    }

    /// Short enough for a map chip: "27°", "40%", "1.2 mm", "18 km/h", "1009 hPa".
    func label(_ hour: PhilippineForecastHour?) -> String {
        guard let value = value(hour) else { return "—" }
        switch self {
        case .temperature: return "\(Int(value.rounded()))°"
        case .rainChance, .clouds, .humidity: return "\(Int(value.rounded()))%"
        case .rainfall: return value == 0 ? "0 mm" : String(format: "%.1f mm", value)
        case .wind: return "\(Int(value.rounded())) km/h"
        case .pressure: return "\(Int(value.rounded())) hPa"
        }
    }

    /// The colour bands, lowest first. `tint` and the legend both read from here.
    var bands: [(upperBound: Double, colour: Color, label: String)] {
        switch self {
        case .temperature:
            [(24, .cyan, "Below 24°"), (29, .yellow, "24–28°"), (34, .orange, "29–33°"), (.infinity, .red, "34° and up")]
        case .rainChance:
            [(25, .green, "Below 25%"), (50, .cyan, "25–49%"), (75, .blue, "50–74%"), (.infinity, .purple, "75% and up")]
        case .rainfall:
            [(0.05, .green, "Dry"), (2.5, .cyan, "Light"), (10, .blue, "Moderate"), (.infinity, .purple, "Heavy, 10 mm+")]
        case .wind:
            [(15, .green, "Below 15 km/h"), (35, .yellow, "15–34"), (60, .orange, "35–59"), (.infinity, .red, "60 km/h and up")]
        case .clouds, .humidity:
            [(45, .cyan, "Below 45%"), (75, .blue, "45–74%"), (.infinity, .indigo, "75% and up")]
        case .pressure:
            [(995, .red, "Below 995 hPa"), (1005, .orange, "995–1004"), (.infinity, .cyan, "1005 hPa and up")]
        }
    }

    func tint(_ hour: PhilippineForecastHour?) -> Color {
        guard let value = value(hour) else { return .gray }
        return bands.first { value < $0.upperBound }?.colour ?? .gray
    }

    /// Low pressure is the notable end; for everything else it is the high end.
    var ranksHighestFirst: Bool { self != .pressure }

    var rankingTitle: String {
        switch self {
        case .temperature: "Hottest at this time"
        case .rainChance: "Most likely rain at this time"
        case .rainfall: "Most rain at this time"
        case .wind: "Windiest at this time"
        case .clouds: "Cloudiest at this time"
        case .humidity: "Most humid at this time"
        case .pressure: "Lowest pressure at this time"
        }
    }
}

private enum WeatherChipMetrics {
    static let glyphSize: CGFloat = 18
    static let nameFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)

    static func sizes(name: String, value: String) -> (full: CGSize, compact: CGSize) {
        let valueWidth = ceil((value as NSString).size(withAttributes: [.font: valueFont]).width)
        let nameWidth = ceil((name as NSString).size(withAttributes: [.font: nameFont]).width)
        // Horizontal padding 8 + glyph + spacing 5 on each side of the name.
        let compact = 8 + glyphSize + 5 + valueWidth + 8
        return (CGSize(width: compact + nameWidth + 5, height: WeatherChipLayout.chipHeight),
                CGSize(width: compact, height: WeatherChipLayout.chipHeight))
    }
}

/// One city: a dot on its exact coordinate, and a chip with the weather symbol and the metric's value
/// joined to it by a short stem. In a crowd it shrinks to the dot alone. The view's frame holds only
/// these parts, so clicks land on them; `WeatherChipLayout.anchor` says where the coordinate sits in it.
private struct WeatherChip: View {
    let name: String
    let value: String
    let tint: Color
    let condition: WeatherPointCondition
    let placement: WeatherChipPlacement
    let isSelected: Bool
    let action: () -> Void
    let hovering: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                if placement.style == .dot {
                    dot
                } else if placement.edge == .above {
                    chip
                    stem
                    dot
                } else {
                    dot
                    stem
                    chip
                }
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover(perform: hovering)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: placement)
        .help("\(name): \(condition.title), \(value)")
        .accessibilityLabel("\(name): \(condition.title), \(value)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dot: some View {
        Circle()
            .fill(tint)
            .frame(width: WeatherChipLayout.dotSize, height: WeatherChipLayout.dotSize)
            .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 1))
            .frame(width: WeatherChipLayout.dotFrame, height: WeatherChipLayout.dotFrame)
            .overlay {
                if isSelected { Circle().stroke(tint, lineWidth: 1.5) }
            }
            .contentShape(Circle())
    }

    private var stem: some View {
        Rectangle()
            .fill(tint.opacity(0.8))
            .frame(width: 1.5, height: WeatherChipLayout.stemLength)
    }

    private var chip: some View {
        HStack(spacing: 5) {
            AnimatedWeatherGlyph(condition: condition, size: WeatherChipMetrics.glyphSize)
                .frame(width: WeatherChipMetrics.glyphSize, height: WeatherChipMetrics.glyphSize)
            if placement.style == .full {
                Text(name)
                    .font(Font(WeatherChipMetrics.nameFont))
                    .foregroundStyle(.white.opacity(0.82))
            }
            Text(value)
                .font(Font(WeatherChipMetrics.valueFont))
                .foregroundStyle(tint)
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .frame(height: WeatherChipLayout.chipHeight)
        .background(Capsule().fill(Color(red: 0.03, green: 0.06, blue: 0.11).opacity(0.92)))
        .overlay(Capsule().stroke(isSelected ? tint : .white.opacity(0.16), lineWidth: isSelected ? 1.5 : 1))
        .shadow(color: .black.opacity(0.55), radius: 4, y: 1)
        .contentShape(Capsule())
    }
}

private struct ThunderstormBeacon: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AnimatedWeatherGlyph(condition: .thunderstorm, size: 42)
                .frame(width: 50, height: 50)
                .shadow(color: .black.opacity(0.85), radius: 5)
        }
        .buttonStyle(.plain)
        .help("Thunderstorm forecast at \(name)")
        .accessibilityLabel("\(name): thunderstorm forecast at the selected time")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct PhilippineWeatherMapView: View {
    private enum MapProvider: String, CaseIterable {
        case apple = "Apple Maps"
        case mapTiler = "MapTiler preview"
        case satellite = "Satellite"
    }

    private enum DetailMode: String, CaseIterable {
        case hourly = "Next 24 hours"
        case daily = "7 days"
    }

    @State private var forecasts: [PhilippineLocationForecast] = []
    @State private var detailMode: DetailMode = .hourly
    @State private var selectedTimeIndex = 0
    @State private var selectedLocationID: String?
    @State private var hoveredLocationID: String?
    @State private var isPlaying = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var placements: [String: WeatherChipPlacement] = [:]
    @State private var lastLayoutSpan: CLLocationDegrees?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedAt: Date?
    @State private var mapTilerKey: String?
    @State private var mapTilerPositions: [String: CGPoint] = [:]
    @State private var mapTilerError: String?
    @State private var mapTilerResetCounter = 0
    @State private var mapTilerCloudRefreshCounter = 0
    @AppStorage("weatherMap.metric") private var metric: WeatherMapMetric = .temperature
    @AppStorage("weatherMap.showNames") private var showNames = true
    @AppStorage("weatherMap.provider") private var mapProvider: MapProvider = .apple

    private let service = PhilippineForecastService()
    private let timeZone = TimeZone(identifier: "Asia/Manila")!

    private var timeline: [Date] { forecasts.first?.hours.map(\.time) ?? [] }
    private var selectedTime: Date? { timeline.indices.contains(selectedTimeIndex) ? timeline[selectedTimeIndex] : nil }
    private var nowIndex: Int { timeline.lastIndex { $0 <= .now } ?? 0 }
    private var selectedForecast: PhilippineLocationForecast? {
        forecasts.first { $0.id == selectedLocationID } ?? forecasts.first
    }
    private var usesMapTiler: Bool { mapProvider == .mapTiler || mapProvider == .satellite }
    private var thunderstormCount: Int { forecasts.filter { $0.hasThunderstorm(at: selectedTimeIndex) }.count }
    /// Changes whenever chip sizes or priorities could; the layout is recomputed on each change.
    private var layoutKey: String {
        "\(selectedTimeIndex)|\(metric.rawValue)|\(showNames)|\(selectedLocationID ?? "")|\(hoveredLocationID ?? "")|\(loadedAt?.timeIntervalSince1970 ?? 0)"
    }

    private func hour(_ forecast: PhilippineLocationForecast) -> PhilippineForecastHour? {
        forecast.hours.indices.contains(selectedTimeIndex) ? forecast.hours[selectedTimeIndex] : nil
    }

    private func condition(_ hour: PhilippineForecastHour?) -> WeatherPointCondition {
        WeatherPointCondition(code: hour?.weatherCode, precipitation: hour?.precipitation)
    }

    var body: some View {
        DashboardSection(title: "Philippines weather map", systemImage: "map.fill") {
            VStack(alignment: .leading, spacing: 14) {
                toolbar

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                if usesMapTiler {
                    if mapTilerKey == nil {
                        Label("Add your MapTiler API key in Settings, then return to this map.", systemImage: "key")
                            .font(.caption).foregroundStyle(.orange)
                    } else if let mapTilerError {
                        Label(mapTilerError, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                if forecasts.isEmpty {
                    if isLoading {
                        ProgressView("Loading the Philippine forecast…")
                            .frame(maxWidth: .infinity, minHeight: 380)
                    } else {
                        ContentUnavailableView("Forecast unavailable", systemImage: "cloud.slash",
                                               description: Text("Refresh the map to try again."))
                            .frame(height: 380)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            mapArea.frame(minWidth: 460, maxWidth: .infinity).frame(height: 720)
                            locationDetail.frame(width: 380, height: 720)
                        }
                        VStack(spacing: 14) {
                            mapArea.frame(height: 640)
                            locationDetail.frame(height: 620)
                        }
                    }
                    timelineControls
                    if mapProvider == .satellite {
                        Text("Cloud imagery: NOAA infrared tiles (latest available). Clouds depict an observation and do not change with the forecast-hour slider; image time is not supplied by this service.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(thunderstormCount == 0
                             ? "No thunderstorms forecast at the 16 sampled locations for this hour. This is not live storm radar."
                             : "\(thunderstormCount) sampled \(thunderstormCount == 1 ? "location has" : "locations have") a thunderstorm forecast for this hour. Icons mark forecast points, not storm coverage or lightning strikes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Text("Forecast samples at 16 Philippine locations, not a continuous weather raster or live radar. Times are Philippine time. Data: Open-Meteo; check PAGASA for official warnings. MapTiler preview uses its own online map service and attribution.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task { if forecasts.isEmpty { await refresh() } }
        .task(id: isPlaying) { await play() }
        .onAppear(perform: reloadMapTilerKey)
        .onChange(of: mapProvider) { _, _ in reloadMapTilerKey() }
        .onReceive(NotificationCenter.default.publisher(for: .mapTilerKeyChanged)) { _ in reloadMapTilerKey() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Basemap", selection: $mapProvider) {
                ForEach(MapProvider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .frame(width: 185)
            if mapProvider != .satellite {
                Picker("Show", selection: $metric) {
                    ForEach(WeatherMapMetric.allCases) { metric in
                        Label(metric.rawValue, systemImage: metric.symbol).tag(metric)
                    }
                }
                .frame(width: 190)
                Toggle("City names", isOn: $showNames)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Button {
                if usesMapTiler { mapTilerResetCounter += 1 }
                else { cameraPosition = .rect(Self.fittedRect(for: forecasts)) }
            } label: {
                Label("Reset view", systemImage: "scope")
            }
            .disabled(forecasts.isEmpty)
            Spacer()
            if let loadedAt {
                Text("Updated \(loadedAt, style: .relative) ago")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if mapProvider == .satellite { mapTilerCloudRefreshCounter += 1 }
                Task { await refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    // MARK: Map

    @ViewBuilder
    private var mapArea: some View {
        ZStack(alignment: .bottomLeading) {
            if usesMapTiler {
                if let mapTilerKey {
                    mapTilerMap(key: mapTilerKey)
                } else {
                    ContentUnavailableView("MapTiler key needed", systemImage: "key",
                                           description: Text("Save your MapTiler API key in Settings, or select Apple Maps."))
                }
            } else {
                appleMap
            }
            if mapProvider != .satellite {
                legend.padding(12)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(metric.rawValue, systemImage: metric.symbol)
                .font(.caption.weight(.semibold))
            ForEach(metric.bands, id: \.label) { band in
                HStack(spacing: 6) {
                    Circle().fill(band.colour).frame(width: 8, height: 8)
                    Text(band.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }

    private func placement(_ forecast: PhilippineLocationForecast) -> WeatherChipPlacement {
        placements[forecast.id] ?? WeatherChipPlacement(style: .dot, edge: .above)
    }

    private func chip(for forecast: PhilippineLocationForecast) -> some View {
        let hour = hour(forecast)
        return WeatherChip(
            name: forecast.location.name,
            value: metric.label(hour),
            tint: metric.tint(hour),
            condition: condition(hour),
            placement: placement(forecast),
            isSelected: selectedForecast?.id == forecast.id,
            action: { selectedLocationID = forecast.id },
            hovering: { hoveredLocationID = $0 ? forecast.id : (hoveredLocationID == forecast.id ? nil : hoveredLocationID) }
        )
    }

    private var appleMap: some View {
        MapReader { proxy in
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
                        ), anchor: WeatherChipLayout.anchor(for: placement(forecast))) {
                            chip(for: forecast)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControls { MapCompass() }
                .onMapCameraChange(frequency: .continuous) { context in
                    // Re-lay out while zooming, but not on every frame of a pan.
                    let span = context.region.span.latitudeDelta
                    if let previous = lastLayoutSpan, previous > 0, abs(span - previous) / previous > 0.04 {
                        lastLayoutSpan = span
                        layOut(size: geometry.size) { proxy.convert($0, to: .local) }
                    } else if lastLayoutSpan == nil {
                        lastLayoutSpan = span
                    }
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    lastLayoutSpan = context.region.span.latitudeDelta
                    layOut(size: geometry.size) { proxy.convert($0, to: .local) }
                }
                .onAppear { layOut(size: geometry.size) { proxy.convert($0, to: .local) } }
                .onChange(of: geometry.size) { _, size in layOut(size: size) { proxy.convert($0, to: .local) } }
                .onChange(of: layoutKey) { _, _ in layOut(size: geometry.size) { proxy.convert($0, to: .local) } }
            }
        }
    }

    private func mapTilerMap(key: String) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                MapTilerWeatherBasemap(
                    key: key,
                    style: mapProvider == .satellite ? .satellite : .landscape,
                    points: forecasts.map { .init(id: $0.id, latitude: $0.location.latitude,
                                                   longitude: $0.location.longitude) },
                    resetCounter: mapTilerResetCounter,
                    cloudRefreshCounter: mapTilerCloudRefreshCounter,
                    onPositions: { positions in
                        mapTilerPositions = positions
                        layOutMapTiler(size: geometry.size)
                    },
                    onStatus: { message in mapTilerError = message }
                )
                .id(key)

                ForEach(forecasts) { forecast in
                    if let position = mapTilerPositions[forecast.id],
                       CGRect(origin: .zero, size: geometry.size).insetBy(dx: -35, dy: -35).contains(position) {
                        if mapProvider == .satellite {
                            if forecast.hasThunderstorm(at: selectedTimeIndex) {
                                ThunderstormBeacon(
                                    name: forecast.location.name,
                                    isSelected: selectedForecast?.id == forecast.id,
                                    action: { selectedLocationID = forecast.id }
                                )
                                .position(position)
                            }
                        } else {
                            // .position centres the view; move it so the dot, not the centre, is on the point.
                            let anchor = WeatherChipLayout.anchor(for: placement(forecast))
                            let height = placement(forecast).style == .dot
                                ? WeatherChipLayout.dotFrame
                                : WeatherChipLayout.chipHeight + WeatherChipLayout.stemLength + WeatherChipLayout.dotFrame
                            chip(for: forecast)
                                .position(x: position.x, y: position.y + (0.5 - anchor.y) * height)
                        }
                    }
                }
            }
            .onChange(of: layoutKey) { _, _ in layOutMapTiler(size: geometry.size) }
            .onChange(of: geometry.size) { _, size in layOutMapTiler(size: size) }
        }
    }

    private func layOutMapTiler(size: CGSize) {
        layOut(size: size) { coordinate in
            forecasts.first { $0.location.latitude == coordinate.latitude && $0.location.longitude == coordinate.longitude }
                .flatMap { mapTilerPositions[$0.id] }
        }
    }

    /// Thunderstorms and the selected metric's notable end get room first.
    private func layOut(size: CGSize, position: (CLLocationCoordinate2D) -> CGPoint?) {
        let candidates = forecasts.map { forecast -> WeatherChipCandidate in
            let hour = hour(forecast)
            let sizes = WeatherChipMetrics.sizes(name: forecast.location.name, value: metric.label(hour))
            let value = metric.value(hour) ?? 0
            let notability = Int((metric.ranksHighestFirst ? value : -value) * 10)
            return WeatherChipCandidate(
                id: forecast.id,
                position: position(CLLocationCoordinate2D(latitude: forecast.location.latitude,
                                                          longitude: forecast.location.longitude)),
                fullSize: sizes.full,
                compactSize: sizes.compact,
                priority: (condition(hour).isThunderstorm ? 1_000_000 : 0) + notability,
                isFocused: forecast.id == selectedForecast?.id || forecast.id == hoveredLocationID
            )
        }
        let next = WeatherChipLayout.place(candidates, viewSize: size, showNames: showNames, previous: placements)
        if next != placements { placements = next }
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
        // Room for chips above the northernmost city and below the southernmost.
        return MKMapRect(x: minX - width * 0.18, y: minY - height * 0.10,
                         width: width * 1.36, height: height * 1.20)
    }

    // MARK: Timeline

    private var timelineControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    if selectedTimeIndex >= timeline.count - 1 { selectedTimeIndex = nowIndex }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill").frame(width: 16)
                }
                .help(isPlaying ? "Pause" : "Play the forecast hour by hour")
                Button("Now") {
                    isPlaying = false
                    selectedTimeIndex = nowIndex
                }
                .disabled(selectedTimeIndex == nowIndex)
                Text(selectedTime.map { formattedTime($0, format: "EEE, MMM d · h a") } ?? "Forecast time")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let selectedTime, selectedTimeIndex != nowIndex {
                    Text(relativeHours(selectedTime)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(selectedTimeIndex == 0)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(selectedTimeIndex >= timeline.count - 1)
            }
            Slider(value: Binding(
                get: { Double(selectedTimeIndex) },
                set: { selectedTimeIndex = Int($0.rounded()) }
            ), in: 0...Double(max(1, timeline.count - 1)), step: 1)
            dayTicks
        }
    }

    /// A day name under the slider at each Philippine midnight.
    private var dayTicks: some View {
        GeometryReader { geometry in
            let last = Double(max(1, timeline.count - 1))
            // The slider's track is inset by about half its knob.
            let inset: CGFloat = 10
            let width = geometry.size.width - inset * 2
            ForEach(dayStarts, id: \.index) { day in
                Text(formattedTime(day.date, format: "EEE d"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: inset + width * CGFloat(Double(day.index) / last), y: 6)
            }
        }
        .frame(height: 14)
    }

    private var dayStarts: [(index: Int, date: Date)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return timeline.enumerated().compactMap { index, date in
            index > 0 && calendar.component(.hour, from: date) == 0 ? (index, date) : nil
        }
    }

    private func step(_ delta: Int) {
        isPlaying = false
        selectedTimeIndex = min(max(0, selectedTimeIndex + delta), max(0, timeline.count - 1))
    }

    private func play() async {
        while isPlaying {
            try? await Task.sleep(for: .milliseconds(650))
            guard isPlaying, !Task.isCancelled else { return }
            if selectedTimeIndex < timeline.count - 1 { selectedTimeIndex += 1 } else { isPlaying = false }
        }
    }

    private func relativeHours(_ date: Date) -> String {
        let hours = Int((date.timeIntervalSince(timeline.indices.contains(nowIndex) ? timeline[nowIndex] : .now) / 3600).rounded())
        return hours > 0 ? "in \(hours) h" : "\(-hours) h ago"
    }

    // MARK: Detail panel

    private var locationDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let forecast = selectedForecast, let hour = hour(forecast) {
                    detailHeader(forecast: forecast, hour: hour)
                    metricTiles(hour)
                    Divider()
                    Picker("Forecast detail", selection: $detailMode) {
                        ForEach(DetailMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if detailMode == .hourly { hourlyRows(forecast) } else { dailyRows(forecast) }
                    Divider()
                }
                ranking
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxHeight: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailHeader(forecast: PhilippineLocationForecast, hour: PhilippineForecastHour) -> some View {
        let condition = condition(hour)
        return VStack(alignment: .leading, spacing: 4) {
            Text(forecast.location.name).font(.title2.weight(.bold))
            Text(selectedTime.map { formattedTime($0, format: "EEEE, MMM d · h a") } ?? "Time unavailable")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                AnimatedWeatherGlyph(condition: condition, size: 48).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 0) {
                    Text(hour.temperature.map { "\(Int($0.rounded()))°C" } ?? "—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(condition.title).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    /// Every metric for this hour. Tapping a tile shows that metric on the map.
    private func metricTiles(_ hour: PhilippineForecastHour) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(WeatherMapMetric.allCases) { item in
                Button { metric = item } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(item.rawValue, systemImage: item.symbol)
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(tileValue(item, hour))
                                .font(.callout.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(item.tint(hour))
                            if item == .wind, let direction = hour.windDirection {
                                // Meteorological direction is where the wind comes from; the arrow shows where it goes.
                                Image(systemName: "location.north.fill")
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(direction + 180))
                                    .help("From \(Int(direction.rounded()))°")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(item == metric ? Color.cyan.opacity(0.14) : Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(item == metric ? Color.cyan.opacity(0.5) : .clear))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == metric ? .isSelected : [])
            }
        }
    }

    private func tileValue(_ item: WeatherMapMetric, _ hour: PhilippineForecastHour) -> String {
        item == .temperature ? hour.temperature.map { "\(Int($0.rounded()))°C" } ?? "—" : item.label(hour)
    }

    private func hourlyRows(_ forecast: PhilippineLocationForecast) -> some View {
        VStack(spacing: 6) {
            ForEach(Array(forecast.hours.dropFirst(selectedTimeIndex).prefix(24)), id: \.time) { future in
                HStack(spacing: 8) {
                    Text(formattedTime(future.time, format: "EEE h a"))
                        .frame(width: 70, alignment: .leading)
                    AnimatedWeatherGlyph(condition: condition(future), size: 16).frame(width: 18, height: 18)
                    Spacer()
                    Text(future.temperature.map { "\(Int($0.rounded()))°" } ?? "—")
                    if metric != .temperature {
                        Text(metric.label(future))
                            .foregroundStyle(metric.tint(future))
                            .frame(width: 70, alignment: .trailing)
                    }
                }
                .font(.caption).monospacedDigit()
            }
        }
    }

    private func dailyRows(_ forecast: PhilippineLocationForecast) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(dailySummaries(for: forecast), id: \.day) { summary in
                HStack(alignment: .firstTextBaseline) {
                    Text(formattedTime(summary.day, format: "EEE d"))
                        .font(.caption.weight(.semibold)).frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(summary.low)–\(summary.high)°C · up to \(summary.rainChance)% rain")
                            .font(.caption)
                        Text(String(format: "%.1f mm total · wind up to %d km/h", summary.rainfall, summary.wind))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .monospacedDigit()
            }
        }
    }

    private var ranking: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.rankingTitle.uppercased())
                .font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(.secondary)
            ForEach(rankedForecasts.prefix(6)) { forecast in
                let hour = hour(forecast)
                Button { selectedLocationID = forecast.id } label: {
                    HStack(spacing: 8) {
                        AnimatedWeatherGlyph(condition: condition(hour), size: 22).frame(width: 24, height: 24)
                        Text(forecast.location.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(metric.label(hour)).monospacedDigit().foregroundStyle(metric.tint(hour))
                    }
                    .font(.caption)
                    .frame(minHeight: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var rankedForecasts: [PhilippineLocationForecast] {
        forecasts.sorted { left, right in
            let a = metric.value(hour(left))
            let b = metric.value(hour(right))
            switch (a, b) {
            case let (a?, b?): return metric.ranksHighestFirst ? a > b : a < b
            case (_?, nil): return true
            default: return false
            }
        }
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

    // MARK: Loading

    private func reloadMapTilerKey() {
        mapTilerKey = MapTilerKeyStore().read()
        mapTilerError = nil
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
            if firstLoad {
                cameraPosition = .rect(Self.fittedRect(for: result))
                selectedTimeIndex = nowIndex
            }
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
