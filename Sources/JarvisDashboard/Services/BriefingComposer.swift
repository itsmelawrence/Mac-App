import Foundation

struct BriefingInput {
    let pendingTaskCount: Int
    let overdueTaskCount: Int
    let activeProjectCount: Int
    let weather: WeatherSnapshot?
    let significantEarthquakeCount: Int
    var downSiteNames: [String] = []
    var slowSiteNames: [String] = []
    var newLeadCount = 0
}

struct BriefingComposer {
    func compose(_ input: BriefingInput, date: Date = .now, calendar: Calendar = .current) -> String {
        var components: [String] = [greeting(for: date, calendar: calendar)]

        if input.overdueTaskCount > 0 {
            components.append("You have \(input.overdueTaskCount) overdue \(noun(input.overdueTaskCount, singular: "task", plural: "tasks")).")
        } else if input.pendingTaskCount > 0 {
            components.append("You have \(input.pendingTaskCount) pending \(noun(input.pendingTaskCount, singular: "task", plural: "tasks")).")
        } else {
            components.append("Your task queue is clear.")
        }

        if input.activeProjectCount > 0 {
            components.append("\(input.activeProjectCount) active \(noun(input.activeProjectCount, singular: "project", plural: "projects")) remain in motion.")
        }

        if input.newLeadCount > 0 {
            components.append(input.newLeadCount == 1
                ? "A new lead is waiting in Leads."
                : "\(input.newLeadCount) new leads are waiting in Leads.")
        }

        if let site = sitesSentence(down: input.downSiteNames, slow: input.slowSiteNames) {
            components.append(site)
        }

        if let weather = input.weather {
            components.append(weatherSentence(weather))
        }

        if input.significantEarthquakeCount > 0 {
            components.append("There are \(input.significantEarthquakeCount) significant regional earthquake \(noun(input.significantEarthquakeCount, singular: "report", plural: "reports")) to review.")
        }

        return components.joined(separator: " ")
    }

    /// A down site leads; slow sites follow. Healthy sites are not mentioned.
    private func sitesSentence(down: [String], slow: [String]) -> String? {
        var parts: [String] = []
        if !down.isEmpty {
            parts.append(down.count == 1 ? "\(down[0]) is down." : "\(down.count) websites are down: \(list(down)).")
        }
        if !slow.isEmpty {
            parts.append(slow.count == 1 ? "\(slow[0]) is responding slowly." : "\(list(slow)) are responding slowly.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// "27 degrees and partly cloudy in Manila", or "… in Manila, with rain" when the condition is a noun.
    private func weatherSentence(_ weather: WeatherSnapshot) -> String {
        let degrees = "It is \(Int(weather.temperature.rounded())) degrees"
        switch weather.weatherCode {
        case 0...3, 45, 48:
            return "\(degrees) and \(weather.condition.lowercased()) in \(weather.locationName)."
        case 95...99:
            return "\(degrees) in \(weather.locationName), with a thunderstorm."
        case 51...67, 71...77, 80...82, 85, 86:
            return "\(degrees) in \(weather.locationName), with \(weather.condition.lowercased())."
        default:
            return "\(degrees) in \(weather.locationName)."
        }
    }

    private func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    private func greeting(for date: Date, calendar: Calendar) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12: "Good morning, Sir."
        case 12..<18: "Good afternoon, Sir."
        default: "Good evening, Sir."
        }
    }

    private func noun(_ count: Int, singular: String, plural: String) -> String {
        count == 1 ? singular : plural
    }
}
