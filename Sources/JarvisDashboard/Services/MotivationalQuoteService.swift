import Foundation

struct MotivationalQuote: Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let author: String
    let source: String
}

enum MotivationalQuoteLibrary {
    static let quotes: [MotivationalQuote] = [
        MotivationalQuote(
            id: "aurelius-good-person",
            text: "Waste no more time arguing what a good person should be. Be one.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "seneca-difficulties",
            text: "Difficulties strengthen the mind, as labour does the body.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "epictetus-suddenly",
            text: "No great thing is created suddenly.",
            author: "Epictetus",
            source: "Discourses"
        ),
        MotivationalQuote(
            id: "nietzsche-why",
            text: "He who has a why to live can bear almost any how.",
            author: "Friedrich Nietzsche",
            source: "Twilight of the Idols"
        ),
        MotivationalQuote(
            id: "seneca-time",
            text: "It is not that we have a short time to live, but that we waste much of it.",
            author: "Seneca",
            source: "On the Shortness of Life"
        ),
        MotivationalQuote(
            id: "aurelius-obstacle",
            text: "The impediment to action advances action. What stands in the way becomes the way.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "epictetus-character",
            text: "First say to yourself what you would be; and then do what you have to do.",
            author: "Epictetus",
            source: "Discourses"
        ),
        MotivationalQuote(
            id: "james-difference",
            text: "Act as if what you do makes a difference. It does.",
            author: "William James",
            source: "Attributed"
        ),
        MotivationalQuote(
            id: "kierkegaard-forward",
            text: "Life can only be understood backwards; but it must be lived forwards.",
            author: "Soren Kierkegaard",
            source: "Journals"
        )
    ]

    static func quote(
        for date: Date,
        offset: Int = 0,
        calendar: Calendar = .current
    ) -> MotivationalQuote {
        precondition(!quotes.isEmpty)
        let startOfDay = calendar.startOfDay(for: date)
        let day = calendar.ordinality(of: .day, in: .era, for: startOfDay) ?? 0
        let index = (day + offset).modulo(quotes.count)
        return quotes[index]
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
