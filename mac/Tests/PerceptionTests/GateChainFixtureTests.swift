import Foundation
import Testing
import Perception
import DebugTools

@Test func gateChainFixturesCoverHarnessRequiredCases() {
    let cases = GateChainFixtureFactory.requiredCases()

    #expect(cases.map(\.id) == [
        "locked-screen",
        "idle-over-threshold",
        "ai-busy",
        "app-changed",
        "window-title-changed",
        "region-hash-changed",
        "recent-input-min-interval",
        "stable-under-force-refresh",
        "force-refresh",
        "privacy-blocked"
    ])
    #expect(cases.map(\.expectedDecisionKind) == [
        .pausedScreenLocked,
        .skipIdle,
        .skipAIBusy,
        .analyze,
        .analyze,
        .analyze,
        .analyze,
        .skipStable,
        .analyze,
        .skipPrivacyBlocked
    ])
}

@Test func gateChainFixturesDeclareExpectedTriggerSignals() {
    let cases = Dictionary(uniqueKeysWithValues: GateChainFixtureFactory.requiredCases().map { ($0.id, $0) })

    #expect(cases["app-changed"]?.expectedSignals == [.appChanged])
    #expect(cases["window-title-changed"]?.expectedSignals == [.windowTitleChanged])
    #expect(cases["region-hash-changed"]?.expectedSignals == [.regionHashChanged])
    #expect(cases["recent-input-min-interval"]?.expectedSignals == [.recentInputActive])
    #expect(cases["force-refresh"]?.expectedSignals == [.forceRefreshInterval])
}

@Test func gateChainFixturesRoundTripThroughJSON() throws {
    let cases = GateChainFixtureFactory.requiredCases()

    let data = try JSONEncoder().encode(cases)
    let decoded = try JSONDecoder().decode([GateChainFixtureCase].self, from: data)

    #expect(decoded == cases)
}
