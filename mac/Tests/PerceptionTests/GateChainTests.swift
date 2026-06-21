import Foundation
import Testing
import Perception
import DebugTools

@Test func gateChainMatchesRequiredFixtures() {
    let gateChain = GateChain()

    for fixture in GateChainFixtureFactory.requiredCases() {
        let result = gateChain.evaluate(input(from: fixture))

        #expect(result.decision.kind == fixture.expectedDecisionKind, "fixture \(fixture.id)")
        #expect(result.decision.triggeredSignals == fixture.expectedSignals, "fixture \(fixture.id)")
        #expect(result.diagnosticEvent.decision == result.decision, "fixture \(fixture.id)")
    }
}

@Test func gateChainDiagnosticEventCarriesSharedEnvelopeFields() {
    let timestamp = Date(timeIntervalSince1970: 1_780_001_000)
    let input = GateChainInput(
        timestamp: timestamp,
        traceId: "trace-gate",
        parentSpanId: "parent-span",
        screenState: .active,
        idleDuration: 2,
        frontAppSnapshot: FrontAppSnapshot(appName: "Safari", windowTitles: ["Article"]),
        secondsSinceLastAnalysis: 120,
        secondsSinceLastAI: 120
    )

    let result = GateChain().evaluate(input)

    #expect(result.diagnosticEvent.timestamp == timestamp)
    #expect(result.diagnosticEvent.traceId == "trace-gate")
    #expect(result.diagnosticEvent.parentSpanId == "parent-span")
    #expect(result.diagnosticEvent.module == "perception")
    #expect(result.diagnosticEvent.decision.kind == .analyze)
    #expect(result.diagnosticEvent.snapshot?.appName == "Safari")
}

@Test func gateChainAppliesConfiguredIntervals() {
    let gateChain = GateChain(parameters: PerceptionParameters(normalMinAIInterval: 20, forceRefreshInterval: 200))
    let recentInput = GateChainInput(
        frontAppSnapshot: FrontAppSnapshot(appName: "Safari"),
        recentInputActive: true,
        secondsSinceLastAnalysis: 199,
        secondsSinceLastAI: 19
    )
    let forceRefresh = GateChainInput(
        frontAppSnapshot: FrontAppSnapshot(appName: "Safari"),
        secondsSinceLastAnalysis: 200,
        secondsSinceLastAI: 0
    )

    #expect(gateChain.evaluate(recentInput).decision.kind == .skipStable)
    #expect(gateChain.evaluate(forceRefresh).decision.triggeredSignals == [.forceRefreshInterval])
}

private func input(from fixture: GateChainFixtureCase) -> GateChainInput {
    GateChainInput(
        screenState: fixture.screenState,
        powerSnapshot: fixture.powerSnapshot,
        idleDuration: fixture.idleDuration,
        frontAppSnapshot: fixture.frontAppSnapshot,
        previousFrontAppSnapshot: fixture.previousFrontAppSnapshot,
        regionHash: fixture.regionHash,
        recentInputActive: fixture.recentInputActive,
        aiBusy: fixture.aiBusy,
        secondsSinceLastAnalysis: fixture.secondsSinceLastAnalysis,
        secondsSinceLastAI: fixture.secondsSinceLastAI
    )
}
