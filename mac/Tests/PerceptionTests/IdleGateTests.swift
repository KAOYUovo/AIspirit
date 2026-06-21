import Foundation
import Testing
import Perception
import DebugTools

@Test func idleGateSkipsCaptureWhenIdleDurationExceedsThreshold() async {
    let result = await IdleGate(detector: MockIdleDetector(idleDuration: 60.1)).evaluate()

    #expect(result.shouldSkipCapture)
    #expect(result.mode == .normal)
    #expect(result.decision?.kind == .skipIdle)
    #expect(result.decision?.reasons == ["idle above threshold"])
    #expect(result.errors.isEmpty)
}

@Test func idleGateDoesNotSkipAtThreshold() {
    let result = IdleGate.evaluate(idleDuration: 60)

    #expect(result.shouldSkipCapture == false)
    #expect(result.decision == nil)
}

@Test func idleGateUsesInjectedThreshold() {
    let parameters = PerceptionParameters(idleThreshold: 10)

    let result = IdleGate.evaluate(idleDuration: 10.1, parameters: parameters)

    #expect(result.shouldSkipCapture)
    #expect(result.decision?.kind == .skipIdle)
}

@Test func idleGateFallsBackToActiveWhenDetectorFails() async {
    let gate = IdleGate(detector: MockIdleDetector(error: .unavailable("idle")))

    let result = await gate.evaluate()

    #expect(result.idleDuration == 0)
    #expect(result.shouldSkipCapture == false)
    #expect(result.decision == nil)
    #expect(result.errors.count == 1)
    #expect(result.errors.first?.isFallbackApplied == true)
}
