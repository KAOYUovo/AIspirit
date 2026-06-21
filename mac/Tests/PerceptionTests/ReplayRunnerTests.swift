import Testing
import Perception
import DebugTools

@Test func replayRunnerCountsAnalyzeSkipAndFallback() async {
    let scenario = ReplayScenario(
        id: "mixed",
        name: "Mixed",
        description: "analyze, skip, fallback",
        events: [
            MockScenarioFactory().make(.busyTyping).events[0],
            MockScenarioFactory().make(.busyTyping).events[1],
            MockScenarioFactory().make(.streamFallback).events[0]
        ]
    )

    let result = await PerceptionReplayRunner().replay(scenario)

    #expect(result.scenarioID == "mixed")
    #expect(result.totalEvents == 3)
    #expect(result.analyzedCount == 1)
    #expect(result.skippedCount == 1)
    #expect(result.fallbackCount == 1)
    #expect(result.decisions.map(\.kind) == [.analyze, .skipStable, .fallback])
    #expect(result.petActions.count == 3)
    #expect(result.mismatches.isEmpty)
}

@Test func replayRunnerSupportsIndexRange() async {
    let scenario = MockScenarioFactory().make(.busyTyping)

    let result = await PerceptionReplayRunner().replay(
        scenario,
        config: PerceptionReplayConfig(startIndex: 1, endIndex: 1)
    )

    #expect(result.totalEvents == 1)
    #expect(result.decisions[0].kind == .skipStable)
}

@Test func replayRunnerAppliesOverrideFeatureFlags() async {
    var override = PerceptionFeatureFlags()
    override.coWatchingStream = true
    override.keyframeExtraction = true

    let result = await PerceptionReplayRunner().replay(
        MockScenarioFactory().make(.busyTyping),
        config: PerceptionReplayConfig(overrideFeatureFlags: override)
    )

    #expect(result.effectiveFeatureFlags.count == result.totalEvents)
    #expect(result.effectiveFeatureFlags.allSatisfy { $0.coWatchingStream && $0.keyframeExtraction })
}

