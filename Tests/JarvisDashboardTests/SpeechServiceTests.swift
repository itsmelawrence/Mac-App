import Testing
@testable import JarvisDashboard

@MainActor
struct SpeechServiceTests {
    @Test func quietHoursSupportOvernightRanges() {
        #expect(SpeechService.isQuietHour(23, start: 22, end: 7))
        #expect(SpeechService.isQuietHour(6, start: 22, end: 7))
        #expect(!SpeechService.isQuietHour(12, start: 22, end: 7))
    }

    @Test func matchingQuietHoursDisableSuppression() {
        #expect(!SpeechService.isQuietHour(12, start: 7, end: 7))
    }
}
