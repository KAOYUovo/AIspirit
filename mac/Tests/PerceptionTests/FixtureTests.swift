import Foundation
import Testing
import Perception
import DebugTools

@Test func mockScenarioFactoryCreatesAllRequiredScenarios() {
    let factory = MockScenarioFactory()

    for kind in MockScenarioKind.allCases {
        let scenario = factory.make(kind)
        #expect(!scenario.id.isEmpty)
        #expect(!scenario.name.isEmpty)
        #expect(!scenario.events.isEmpty)
        #expect(scenario.events.allSatisfy { $0.module == "perception" })
        #expect(scenario.events.allSatisfy { !$0.traceId.isEmpty && !$0.spanId.isEmpty })
    }
}

@Test func busyTypingScenarioSuppressesBubblesAndUsesBusyState() {
    let scenario = MockScenarioFactory().make(.busyTyping)

    #expect(scenario.id == "busy-typing")
    #expect(scenario.events.contains { $0.snapshot?.attentionState == .busy })
    #expect(scenario.events.contains { event in
        event.petActions.contains { $0.type == .suppressBubble }
    })
}

@Test func screenLockedScenarioHasNoSnapshotAndPauses() {
    let scenario = MockScenarioFactory().make(.screenLocked)
    let event = scenario.events[0]

    #expect(event.mode == .paused)
    #expect(event.snapshot == nil)
    #expect(event.coWatchingSnapshot == nil)
    #expect(event.decision.kind == .pausedScreenLocked)
}

@Test func fixtureWriterAndLoaderRoundTripJSONL() throws {
    let scenario = MockScenarioFactory().make(.coWatchingSports)
    let writer = FixtureWriter()
    let loader = FixtureLoader()

    let data = try writer.jsonlData(for: scenario)
    let loaded = try loader.loadScenario(
        fromJSONLData: data,
        id: scenario.id,
        name: scenario.name,
        description: scenario.description
    )

    #expect(loaded == scenario)
    let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
    #expect(lines.count == scenario.events.count)
}

@Test func fixtureWriterAndLoaderRoundTripFile() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AIspiritMacFixtureTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let scenario = MockScenarioFactory().make(.streamFallback)
    let fileURL = root.appendingPathComponent("stream-fallback.jsonl")

    try FixtureWriter().write(scenario, to: fileURL)
    let loaded = try FixtureLoader().loadScenario(
        from: fileURL,
        name: scenario.name,
        description: scenario.description
    )

    #expect(loaded.id == "stream-fallback")
    #expect(loaded.events == scenario.events)
    #expect(loaded.events[0].decision.fallbacks == ["multiFrameSingleCapture"])
}

