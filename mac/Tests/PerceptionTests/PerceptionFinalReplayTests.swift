import Foundation
import Testing
import Perception
import DebugTools

@Test func allRequiredReplayFixturesSatisfyHarnessAcceptance() async throws {
    let factory = MockScenarioFactory()
    let runner = PerceptionReplayRunner()

    try await assertBusyTyping(factory.make(.busyTyping), runner: runner)
    try await assertSwitchToChat(factory.make(.switchToChat), runner: runner)
    try await assertStaticReading(factory.make(.staticReading), runner: runner)
    try await assertScreenLocked(factory.make(.screenLocked), runner: runner)
    try await assertCoWatchingSports(factory.make(.coWatchingSports), runner: runner)
    try await assertStreamFallback(factory.make(.streamFallback), runner: runner)
}

@Test func allRequiredReplayFixturesRoundTripThroughJSONLAndReplay() async throws {
    let factory = MockScenarioFactory()
    let writer = FixtureWriter()
    let loader = FixtureLoader()
    let runner = PerceptionReplayRunner()

    for kind in MockScenarioKind.allCases {
        let scenario = factory.make(kind)
        let data = try writer.jsonlData(for: scenario)
        let loaded = try loader.loadScenario(
            fromJSONLData: data,
            id: scenario.id,
            name: scenario.name,
            description: scenario.description
        )
        let result = await runner.replay(loaded)

        #expect(loaded == scenario, "fixture \(scenario.id) should round-trip through JSONL")
        #expect(result.scenarioID == scenario.id, "fixture \(scenario.id)")
        #expect(result.totalEvents == scenario.events.count, "fixture \(scenario.id)")
        #expect(result.decisions == scenario.events.map(\.decision), "fixture \(scenario.id)")
        #expect(result.mismatches.isEmpty, "fixture \(scenario.id)")
    }
}

private func assertBusyTyping(_ scenario: ReplayScenario, runner: PerceptionReplayRunner) async throws {
    let result = await runner.replay(scenario)
    let busyCount = scenario.events.filter { $0.snapshot?.attentionState == .busy }.count

    #expect(scenario.id == "busy-typing")
    #expect(busyCount > scenario.events.count / 2)
    #expect(scenario.events.contains { event in
        event.petActions.contains { $0.type == .suppressBubble && $0.payload["reason"] == "attentionState=busy" }
    })
    #expect(result.analyzedCount == 2)
    #expect(result.skippedCount == 1)
    #expect(result.fallbackCount == 0)
}

private func assertSwitchToChat(_ scenario: ReplayScenario, runner: PerceptionReplayRunner) async throws {
    let result = await runner.replay(scenario)

    #expect(scenario.id == "switch-to-chat")
    #expect(result.decisions.first?.kind == .skipStable)
    #expect(result.decisions.last?.kind == .analyze)
    #expect(result.decisions.last?.triggeredSignals == [.appChanged, .windowTitleChanged])
}

private func assertStaticReading(_ scenario: ReplayScenario, runner: PerceptionReplayRunner) async throws {
    let result = await runner.replay(scenario)

    #expect(scenario.id == "static-reading")
    #expect(result.analyzedCount == 1)
    #expect(result.skippedCount == 2)
    #expect(result.decisions.last?.triggeredSignals == [.forceRefreshInterval])
}

private func assertScreenLocked(_ scenario: ReplayScenario, runner: PerceptionReplayRunner) async throws {
    let result = await runner.replay(scenario)

    #expect(scenario.id == "screen-locked")
    #expect(result.decisions == [GateDecision(
        kind: .pausedScreenLocked,
        reasons: ["screen locked"],
        triggeredSignals: [],
        fallbacks: []
    )])
    #expect(scenario.events.allSatisfy { $0.snapshot == nil && $0.coWatchingSnapshot == nil })
}

private func assertCoWatchingSports(_ scenario: ReplayScenario, runner: PerceptionReplayRunner) async throws {
    let result = await runner.replay(scenario)

    #expect(scenario.id == "co-watching-sports")
    #expect(result.analyzedCount == scenario.events.count)
    #expect(scenario.events.allSatisfy { $0.mode == .coWatching })
    #expect(scenario.events.allSatisfy { $0.coWatchingSnapshot?.contentType == .sports })
    #expect(scenario.events.contains { event in
        event.petActions.contains { $0.type == .enterCoWatching }
    })
}

private func assertStreamFallback(_ scenario: ReplayScenario, runner: PerceptionReplayRunner) async throws {
    let result = await runner.replay(scenario)

    #expect(scenario.id == "stream-fallback")
    #expect(result.fallbackCount == 1)
    #expect(result.decisions.first?.kind == .fallback)
    #expect(result.decisions.first?.fallbacks == ["multiFrameSingleCapture"])
    #expect(scenario.events.first?.errors.first?.isFallbackApplied == true)
}
