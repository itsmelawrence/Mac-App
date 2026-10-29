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
            author: "Søren Kierkegaard",
            source: "Journals"
        ),
        MotivationalQuote(
            id: "aurelius-habitual-thoughts",
            text: "Such as are your habitual thoughts, such also will be the character of your mind.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "aurelius-not-right",
            text: "If it is not right, do not do it; if it is not true, do not say it.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "aurelius-last-act",
            text: "Do every act of your life as if it were the last.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "aurelius-avenging",
            text: "The best way of avenging yourself is not to become like the wrongdoer.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "aurelius-loss",
            text: "Loss is nothing else but change.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "aurelius-present",
            text: "Confine yourself to the present.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "aurelius-external",
            text: "If you are distressed by anything external, the pain is not due to the thing itself, but to your estimate of it; and this you have the power to revoke at any moment.",
            author: "Marcus Aurelius",
            source: "Meditations"
        ),
        MotivationalQuote(
            id: "seneca-imagination",
            text: "We are more often frightened than hurt; and we suffer more from imagination than from reality.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "seneca-postponing",
            text: "While we are postponing, life speeds by.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "seneca-tale",
            text: "As is a tale, so is life: not how long it is, but how good it is, is what matters.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "seneca-craves-more",
            text: "It is not the man who has too little, but the man who craves more, that is poor.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "seneca-wise-by-chance",
            text: "No man was ever wise by chance.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "seneca-begin-at-once",
            text: "Begin at once to live, and count each separate day as a separate life.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "seneca-harbour",
            text: "When a man does not know what harbour he is making for, no wind is the right wind.",
            author: "Seneca",
            source: "Letters from a Stoic"
        ),
        MotivationalQuote(
            id: "seneca-life-is-long",
            text: "Life is long if you know how to use it.",
            author: "Seneca",
            source: "On the Shortness of Life"
        ),
        MotivationalQuote(
            id: "epictetus-opinions",
            text: "Men are disturbed not by things, but by the opinions about things.",
            author: "Epictetus",
            source: "Enchiridion"
        ),
        MotivationalQuote(
            id: "epictetus-foolish",
            text: "If you want to improve, be content to be thought foolish and stupid.",
            author: "Epictetus",
            source: "Enchiridion"
        ),
        MotivationalQuote(
            id: "epictetus-tranquil",
            text: "Seek not that the things which happen should happen as you wish; but wish the things which happen to be as they are, and you will have a tranquil flow of life.",
            author: "Epictetus",
            source: "Enchiridion"
        ),
        MotivationalQuote(
            id: "epictetus-master",
            text: "No man is free who is not master of himself.",
            author: "Epictetus",
            source: "Fragments"
        ),
        MotivationalQuote(
            id: "durant-habit",
            text: "We are what we repeatedly do. Excellence, then, is not an act, but a habit.",
            author: "Will Durant",
            source: "The Story of Philosophy"
        ),
        MotivationalQuote(
            id: "confucius-knowledge",
            text: "When you know a thing, to hold that you know it; and when you do not know a thing, to allow that you do not know it; this is knowledge.",
            author: "Confucius",
            source: "Analects"
        ),
        MotivationalQuote(
            id: "confucius-modest",
            text: "The superior man is modest in his speech, but exceeds in his actions.",
            author: "Confucius",
            source: "Analects"
        ),
        MotivationalQuote(
            id: "confucius-in-himself",
            text: "What the superior man seeks is in himself. What the mean man seeks is in others.",
            author: "Confucius",
            source: "Analects"
        ),
        MotivationalQuote(
            id: "laozi-single-step",
            text: "The journey of a thousand miles begins with a single step.",
            author: "Lao Tzu",
            source: "Tao Te Ching"
        ),
        MotivationalQuote(
            id: "franklin-well-done",
            text: "Well done is better than well said.",
            author: "Benjamin Franklin",
            source: "Poor Richard's Almanack"
        ),
        MotivationalQuote(
            id: "franklin-lost-time",
            text: "Lost time is never found again.",
            author: "Benjamin Franklin",
            source: "Poor Richard's Almanack"
        ),
        MotivationalQuote(
            id: "thoreau-simplify",
            text: "Our life is frittered away by detail. Simplify, simplify.",
            author: "Henry David Thoreau",
            source: "Walden"
        ),
        MotivationalQuote(
            id: "thoreau-confidently",
            text: "If one advances confidently in the direction of his dreams, and endeavors to live the life which he has imagined, he will meet with a success unexpected in common hours.",
            author: "Henry David Thoreau",
            source: "Walden"
        ),
        MotivationalQuote(
            id: "emerson-enthusiasm",
            text: "Nothing great was ever achieved without enthusiasm.",
            author: "Ralph Waldo Emerson",
            source: "Circles"
        ),
        MotivationalQuote(
            id: "emerson-trust-thyself",
            text: "Trust thyself: every heart vibrates to that iron string.",
            author: "Ralph Waldo Emerson",
            source: "Self-Reliance"
        ),
        MotivationalQuote(
            id: "roosevelt-critic",
            text: "It is not the critic who counts; not the man who points out how the strong man stumbles.",
            author: "Theodore Roosevelt",
            source: "Citizenship in a Republic"
        ),
        MotivationalQuote(
            id: "nietzsche-stronger",
            text: "What does not kill me makes me stronger.",
            author: "Friedrich Nietzsche",
            source: "Twilight of the Idols"
        ),
        MotivationalQuote(
            id: "frankl-change-ourselves",
            text: "When we are no longer able to change a situation, we are challenged to change ourselves.",
            author: "Viktor Frankl",
            source: "Man's Search for Meaning"
        ),
        MotivationalQuote(
            id: "frankl-attitude",
            text: "Everything can be taken from a man but one thing: the last of the human freedoms, to choose one's attitude in any given set of circumstances, to choose one's own way.",
            author: "Viktor Frankl",
            source: "Man's Search for Meaning"
        ),
        MotivationalQuote(
            id: "pascal-chamber",
            text: "All the unhappiness of men arises from one single fact, that they cannot stay quietly in their own chamber.",
            author: "Blaise Pascal",
            source: "Pensées"
        ),
        MotivationalQuote(
            id: "plato-beginning",
            text: "The beginning is the most important part of the work.",
            author: "Plato",
            source: "The Republic"
        ),
        MotivationalQuote(
            id: "socrates-examined",
            text: "The unexamined life is not worth living.",
            author: "Socrates",
            source: "Plato, Apology"
        ),
        MotivationalQuote(
            id: "aristotle-swallow",
            text: "For as it is not one swallow or a fine day that makes a spring, so it is not one day or a short time that makes a man blessed and happy.",
            author: "Aristotle",
            source: "Nicomachean Ethics"
        ),
        MotivationalQuote(
            id: "camus-invincible-summer",
            text: "In the midst of winter, I found there was, within me, an invincible summer.",
            author: "Albert Camus",
            source: "Return to Tipasa"
        )
    ]

    /// The quote for a day. Each pass through the library uses its own shuffled order, so every quote
    /// appears once before any repeats, and consecutive passes don't follow the same sequence.
    /// `offset` steps forward through that sequence ("next quote").
    static func quote(
        for date: Date,
        offset: Int = 0,
        calendar: Calendar = .current
    ) -> MotivationalQuote {
        precondition(!quotes.isEmpty)
        let startOfDay = calendar.startOfDay(for: date)
        let day = calendar.ordinality(of: .day, in: .era, for: startOfDay) ?? 0
        let position = day + offset
        let count = quotes.count
        let pass = (position - position.modulo(count)) / count
        return quotes[order(forPass: pass)[position.modulo(count)]]
    }

    static func order(forPass pass: Int) -> [Int] {
        var order = shuffledIndices(pass)
        // Don't show the same quote on the last day of one pass and the first day of the next.
        if order.count > 2, order[0] == shuffledIndices(pass - 1).last {
            order.swapAt(0, 1)
        }
        return order
    }

    private static func shuffledIndices(_ pass: Int) -> [Int] {
        var generator = SplitMix64(seed: UInt64(bitPattern: Int64(pass)) &+ 0x5EED_0F_0E7A15)
        return Array(quotes.indices).shuffled(using: &generator)
    }
}

/// A small seeded generator, so a day's quote is the same on every launch.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let remainder = self % divisor
        return remainder >= 0 ? remainder : remainder + divisor
    }
}
