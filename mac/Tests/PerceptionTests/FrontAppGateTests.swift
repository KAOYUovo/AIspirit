import Foundation
import Testing
import Perception
import DebugTools

@Test func frontAppGateBlocksCaptureForBlockedAppNameBeforeCapture() {
    let snapshot = FrontAppSnapshot(appName: "1Password", bundleIdentifier: "com.1password.1password")

    let result = FrontAppGate.evaluate(snapshot: snapshot)

    #expect(result.shouldBlockCapture)
    #expect(result.decision?.kind == .skipPrivacyBlocked)
    #expect(result.privacyMatch?.field == .appName)
}

@Test func frontAppGateBlocksCaptureForBlockedWindowTitleBeforeCapture() {
    let blocklist = PrivacyBlocklist(appNamePatterns: [], bundleIdentifierPatterns: [], windowTitlePatterns: ["secret"])
    let snapshot = FrontAppSnapshot(appName: "Safari", windowTitles: ["Secret recovery key"])

    let result = FrontAppGate.evaluate(snapshot: snapshot, blocklist: blocklist)

    #expect(result.shouldBlockCapture)
    #expect(result.decision?.kind == .skipPrivacyBlocked)
    #expect(result.privacyMatch?.field == .windowTitle)
}

@Test func frontAppGateEmitsAnalyzeForAppChange() {
    let previous = FrontAppSnapshot(appName: "Safari", bundleIdentifier: "com.apple.Safari")
    let current = FrontAppSnapshot(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")

    let result = FrontAppGate.evaluate(snapshot: current, previousSnapshot: previous, blocklist: emptyBlocklist)

    #expect(result.shouldBlockCapture == false)
    #expect(result.decision?.kind == .analyze)
    #expect(result.decision?.triggeredSignals == [.appChanged])
}

@Test func frontAppGateEmitsAnalyzeForWindowTitleChange() {
    let previous = FrontAppSnapshot(appName: "Safari", windowTitles: ["Article"])
    let current = FrontAppSnapshot(appName: "Safari", windowTitles: ["Dashboard"])

    let result = FrontAppGate.evaluate(snapshot: current, previousSnapshot: previous, blocklist: emptyBlocklist)

    #expect(result.shouldBlockCapture == false)
    #expect(result.decision?.kind == .analyze)
    #expect(result.decision?.triggeredSignals == [.windowTitleChanged])
}

@Test func frontAppGatePrivacyBlockTakesPrecedenceOverChangeSignals() {
    let previous = FrontAppSnapshot(appName: "Safari", windowTitles: ["Article"])
    let current = FrontAppSnapshot(appName: "Safari", windowTitles: ["Private key"])

    let result = FrontAppGate.evaluate(snapshot: current, previousSnapshot: previous)

    #expect(result.shouldBlockCapture)
    #expect(result.decision?.kind == .skipPrivacyBlocked)
    #expect(result.decision?.triggeredSignals.isEmpty == true)
}

@Test func frontAppGateFallsBackToUnknownWhenDetectorFails() async {
    let gate = FrontAppGate(detector: MockFrontAppDetector(error: .unavailable("front app")))

    let result = await gate.evaluate()

    #expect(result.snapshot == .unknown)
    #expect(result.shouldBlockCapture == false)
    #expect(result.decision == nil)
    #expect(result.errors.first?.isFallbackApplied == true)
}

@Test func frontAppDetectorReturnsSafeSnapshotShape() async throws {
    let snapshot = try await NSWorkspaceFrontAppDetector().detect()

    #expect(snapshot.appName.isEmpty == false)
}

private let emptyBlocklist = PrivacyBlocklist(
    appNamePatterns: [],
    bundleIdentifierPatterns: [],
    windowTitlePatterns: []
)
