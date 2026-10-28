import AVFoundation
import Foundation

struct SpeechVoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
}

@MainActor
final class SpeechService: NSObject, ObservableObject {
    static let shared = SpeechService()

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.isEnabled)
            if !isEnabled { stop() }
        }
    }

    @Published var speakWakeBriefings: Bool {
        didSet { defaults.set(speakWakeBriefings, forKey: Keys.speakWakeBriefings) }
    }

    @Published var speakCriticalAlerts: Bool {
        didSet { defaults.set(speakCriticalAlerts, forKey: Keys.speakCriticalAlerts) }
    }

    @Published var quietHoursEnabled: Bool {
        didSet { defaults.set(quietHoursEnabled, forKey: Keys.quietHoursEnabled) }
    }

    @Published var quietStartHour: Int {
        didSet { defaults.set(quietStartHour, forKey: Keys.quietStartHour) }
    }

    @Published var quietEndHour: Int {
        didSet { defaults.set(quietEndHour, forKey: Keys.quietEndHour) }
    }

    @Published var voiceIdentifier: String {
        didSet { defaults.set(voiceIdentifier, forKey: Keys.voiceIdentifier) }
    }

    @Published var rate: Double {
        didSet { defaults.set(rate, forKey: Keys.rate) }
    }

    @Published var pitch: Double {
        didSet { defaults.set(pitch, forKey: Keys.pitch) }
    }

    @Published var volume: Double {
        didSet { defaults.set(volume, forKey: Keys.volume) }
    }

    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let defaults: UserDefaults

    var availableVoices: [SpeechVoiceOption] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("en") }
            .map { SpeechVoiceOption(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted {
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        speakWakeBriefings = defaults.object(forKey: Keys.speakWakeBriefings) as? Bool ?? true
        speakCriticalAlerts = defaults.object(forKey: Keys.speakCriticalAlerts) as? Bool ?? true
        quietHoursEnabled = defaults.object(forKey: Keys.quietHoursEnabled) as? Bool ?? true
        quietStartHour = defaults.object(forKey: Keys.quietStartHour) as? Int ?? 22
        quietEndHour = defaults.object(forKey: Keys.quietEndHour) as? Int ?? 7
        rate = defaults.object(forKey: Keys.rate) as? Double ?? 0.47
        pitch = defaults.object(forKey: Keys.pitch) as? Double ?? 0.92
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.9

        voiceIdentifier = defaults.string(forKey: Keys.voiceIdentifier) ?? ""

        super.init()
        synthesizer.delegate = self
    }

    func speak(_ message: String, interrupting: Bool = true) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !trimmed.isEmpty else { return }

        if interrupting, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = Float(rate)
        utterance.pitchMultiplier = Float(pitch)
        utterance.volume = Float(volume)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    func speakWakeBriefing(_ message: String, now: Date = .now, calendar: Calendar = .current) {
        guard isEnabled, speakWakeBriefings, !isQuietHour(now: now, calendar: calendar) else { return }
        speak(message)
    }

    func speakNewCriticalAlert(
        from alerts: [IntelligenceAlert],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        guard isEnabled, speakCriticalAlerts, !isQuietHour(now: now, calendar: calendar) else { return }

        let memory = RecentAlertIDs(key: Keys.spokenCriticalAlertIDs, defaults: defaults)
        let spoken = Set(memory.load())
        guard let alert = alerts.first(where: { $0.severity == .critical && !spoken.contains($0.id) }) else {
            return
        }

        memory.remember([alert.id])
        speak("Critical alert. \(alert.title). \(alert.detail)")
    }

    func preview() {
        speak("Good evening, Sir. JARVIS voice systems are online and operating normally.")
    }

    func isQuietHour(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        return Self.isQuietHour(
            calendar.component(.hour, from: now),
            start: quietStartHour,
            end: quietEndHour
        )
    }

    static func isQuietHour(_ hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        if start < end { return (start..<end).contains(hour) }
        return hour >= start || hour < end
    }

    private enum Keys {
        static let isEnabled = "speech.isEnabled"
        static let speakWakeBriefings = "speech.speakWakeBriefings"
        static let speakCriticalAlerts = "speech.speakCriticalAlerts"
        static let quietHoursEnabled = "speech.quietHoursEnabled"
        static let quietStartHour = "speech.quietStartHour"
        static let quietEndHour = "speech.quietEndHour"
        static let voiceIdentifier = "speech.voiceIdentifier"
        static let rate = "speech.rate"
        static let pitch = "speech.pitch"
        static let volume = "speech.volume"
        static let spokenCriticalAlertIDs = "speech.spokenCriticalAlertIDs"
    }
}

extension SpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in self?.isSpeaking = false }
    }
}
