import Foundation

enum WeatherPointCondition: Equatable, Sendable {
    case clear, partlyCloudy, cloudy, fog, showers, rain, heavyRain, thunderstorm, unknown

    init(code: Int?, precipitation: Double?) {
        guard let code else { self = .unknown; return }
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .showers
        case 95...99: self = .thunderstorm
        case 65, 82: self = .heavyRain
        case 61, 63, 80, 81: self = (precipitation ?? 0) >= 7.5 ? .heavyRain : .rain
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .clear: "Clear"
        case .partlyCloudy: "Partly cloudy"
        case .cloudy: "Cloudy"
        case .fog: "Fog"
        case .showers: "Light showers"
        case .rain: "Rain"
        case .heavyRain: "Heavy rain"
        case .thunderstorm: "Thunderstorm"
        case .unknown: "Conditions unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .clear: "sun.max.fill"
        case .partlyCloudy: "cloud.sun.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .showers: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .thunderstorm: "cloud.bolt.rain.fill"
        case .unknown: "questionmark"
        }
    }

    var isThunderstorm: Bool { self == .thunderstorm }
}

enum WeatherRainBand: Equatable, Sendable {
    case low, moderate, high, extreme, thunderstorm, unavailable

    init(chance: Int?, thunderstorm: Bool) {
        guard let chance else { self = .unavailable; return }
        if thunderstorm { self = .thunderstorm }
        else if chance < 30 { self = .low }
        else if chance < 60 { self = .moderate }
        else if chance < 80 { self = .high }
        else { self = .extreme }
    }

    var label: String {
        switch self {
        case .low: "Under 30%"
        case .moderate: "30–59%"
        case .high: "60–79%"
        case .extreme: "80% and above"
        case .thunderstorm: "Thunderstorm"
        case .unavailable: "No data"
        }
    }
}
