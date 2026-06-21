import Foundation
import Testing
import Perception
import DebugTools

@Test func schedulerRunsVLMWhenGateAllowsAnalysis() async throws {
    let analyzer = MockVLMAnalyzer(results: [
        .success(VLMAnalysisResult(summary: "changed", contentType: .unknown))
    ])
    let scheduler = PerceptionScheduler(
        analyzer: analyzer,
        parameters: PerceptionParameters(vlmTimeout: 1, vlmMaxPerHour: 2)
    )

    let result = await scheduler.runTick(
        GateChainInput(
            traceId: "trace-analyze",
            frontAppSnapshot: FrontAppSnapshot(appName: "Safari"),
            previousFrontAppSnapshot: FrontAppSnapshot(appName: "Xcode"),
            secondsSinceLastAnalysis: 10,
            secondsSinceLastAI: 20
        )
    )

    let invocations = await analyzer.invocations
    #expect(result.outcome == .analyzed)
    #expect(result.didInvokeVLM)
    #expect(result.analysis?.summary == "changed")
    #expect(invocations.count == 1)
    #expect(invocations[0].traceId == "trace-analyze")
    #expect(result.diagnosticEvent.decision.kind == .analyze)
}

@Test func schedulerSkipsAndKeepsLatestTickWhenAIBusy() async {
    let analyzer = MockVLMAnalyzer(suspendsUntilReleased: true, suspensionCount: 1)
    let scheduler = PerceptionScheduler(
        analyzer: analyzer,
        parameters: PerceptionParameters(vlmTimeout: 1, vlmMaxPerHour: 10)
    )

    let firstTask = Task {
        await scheduler.runTick(analyzeInput(traceId: "trace-first"))
    }

    while await analyzer.invocations.isEmpty {
        await Task.yield()
    }

    let skippedOld = await scheduler.runTick(analyzeInput(traceId: "trace-old"))
    let skippedLatest = await scheduler.runTick(analyzeInput(traceId: "trace-latest"))
    let pendingBeforeRelease = await scheduler.pendingTick()

    await analyzer.releaseAll()
    _ = await firstTask.value

    let drained = await scheduler.drainLatestTick()
    let invocations = await analyzer.invocations

    #expect(skippedOld.outcome == .skipped)
    #expect(skippedOld.diagnosticEvent.decision.kind == .skipAIBusy)
    #expect(skippedLatest.outcome == .skipped)
    #expect(pendingBeforeRelease?.traceId == "trace-latest")
    #expect(drained?.diagnosticEvent.traceId == "trace-latest")
    #expect(invocations.map(\.traceId) == ["trace-first", "trace-latest"])
}

@Test func schedulerAppliesHourlyVLMBudget() async {
    let analyzer = MockVLMAnalyzer(results: [
        .success(VLMAnalysisResult(summary: "one", contentType: .unknown))
    ])
    let scheduler = PerceptionScheduler(
        analyzer: analyzer,
        parameters: PerceptionParameters(vlmTimeout: 1, vlmMaxPerHour: 1)
    )

    let first = await scheduler.runTick(analyzeInput(traceId: "trace-budget-1"))
    let second = await scheduler.runTick(analyzeInput(traceId: "trace-budget-2"))
    let invocations = await analyzer.invocations

    #expect(first.outcome == .analyzed)
    #expect(second.outcome == .skipped)
    #expect(second.didInvokeVLM == false)
    #expect(second.diagnosticEvent.decision.kind == .skipStable)
    #expect(second.diagnosticEvent.decision.reasons.contains("VLM hourly budget exhausted"))
    #expect(invocations.count == 1)
}

@Test func schedulerConvertsVLMTimeoutToFallbackDiagnostic() async {
    let analyzer = MockVLMAnalyzer(delayNanoseconds: 200_000_000)
    let scheduler = PerceptionScheduler(
        analyzer: analyzer,
        parameters: PerceptionParameters(vlmTimeout: 0.01, vlmMaxPerHour: 10)
    )

    let result = await scheduler.runTick(analyzeInput(traceId: "trace-timeout"))

    #expect(result.outcome == .fallback)
    #expect(result.didInvokeVLM)
    #expect(result.diagnosticEvent.decision.kind == .fallback)
    #expect(result.diagnosticEvent.errors.count == 1)
    #expect(result.diagnosticEvent.errors[0].code == "vlmTimeout")
}

private func analyzeInput(traceId: String) -> GateChainInput {
    GateChainInput(
        traceId: traceId,
        frontAppSnapshot: FrontAppSnapshot(appName: "Safari"),
        previousFrontAppSnapshot: FrontAppSnapshot(appName: "Xcode"),
        secondsSinceLastAnalysis: 10,
        secondsSinceLastAI: 20
    )
}
