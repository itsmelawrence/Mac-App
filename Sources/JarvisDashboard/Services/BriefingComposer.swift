import Foundation

struct BriefingInput {
    let pendingTaskCount: Int
    let overdueTaskCount: Int
    let activeProjectCount: Int
    let weather: WeatherSnapshot?
    let significantEarthquakeCount: Int
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

        if let weather = input.weather {
            components.append("It is \(Int(weather.temperature.rounded())) degrees in \(weather.locationName), with \(weather.condition.lowercased()).")
        }

        if input.significantEarthquakeCount > 0 {
            components.append("There are \(input.significantEarthquakeCount) significant regional earthquake \(noun(input.significantEarthquakeCount, singular: "report", plural: "reports")) to review.")
        }

        return components.joined(separator: " ")
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
