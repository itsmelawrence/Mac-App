import Testing
@testable import JarvisDashboard

@MainActor
struct SplashReadinessTests {
    @Test func waitsForAnimationAndDashboardBeforeDismissal() {
        let state = AppState()

        #expect(state.isSplashVisible)
        #expect(!state.canDismissSplash)

        state.markSplashAnimationFinished()
        #expect(!state.canDismissSplash)

        state.markDashboardReady()
        #expect(state.canDismissSplash)

        state.completeSplash()
        #expect(!state.isSplashVisible)
        #expect(!state.canDismissSplash)
    }
}
