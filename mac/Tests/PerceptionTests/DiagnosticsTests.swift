import Foundation
import Testing
import Perception

@Test func diagnosticEventRoundTripsWithSharedEnvelopeFields() throws {
    let event = makeEvent()

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(event)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(PerceptionDiagnosticEvent.self, from: data)

    #expect(decoded == event)
    #expect(decoded.schemaVersion == 1)
    #expect(decoded.traceId == "trace-1")
    #expect(decoded.spanId == "span-perception-1")
    #expect(decoded.parentSpanId == nil)
    #expect(decoded.module == "perception")
}

@Test func jsonlWriterWritesOneJSONEventPerLine() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let fileURL = root.appendingPathComponent("perception.jsonl")
    let writer = JSONLWriter(fileURL: fileURL)

    await writer.append(makeEvent(id: "tick-1"))
    await writer.append(makeEvent(id: "tick-2"))
    await writer.flush()

    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.count == 3)
    #expect(lines[0].contains("\"id\":\"tick-1\""))
    #expect(lines[1].contains("\"id\":\"tick-2\""))
    #expect(lines[2].isEmpty)
    #expect(await writer.failureCount == 0)
}

@Test func perceptionDiagnosticsWritesDatedJSONLAndDisabledNoOps() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let diagnostics = PerceptionDiagnostics(enabled: true, rootDirectory: root)

    await diagnostics.record(makeEvent(timestamp: utcDate(year: 2026, month: 6, day: 21)))
    await diagnostics.flush()

    let fileURL = root.appendingPathComponent("perception/2026-06-21/perception.jsonl")
    let contents = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(contents.contains("\"traceId\":\"trace-1\""))
    #expect(contents.contains("\"spanId\":\"span-perception-1\""))

    let disabledRoot = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: disabledRoot) }
    let disabled = PerceptionDiagnostics(enabled: false, rootDirectory: disabledRoot)
    await disabled.record(makeEvent())
    await disabled.flush()
    #expect(!FileManager.default.fileExists(atPath: disabledRoot.path))
}

@Test func perceptionDiagnosticsClearsOldDatedLogs() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let diagnostics = PerceptionDiagnostics(enabled: true, rootDirectory: root)

    await diagnostics.record(makeEvent(id: "old", timestamp: utcDate(year: 2026, month: 6, day: 1)))
    await diagnostics.record(makeEvent(id: "new", timestamp: utcDate(year: 2026, month: 6, day: 20)))
    await diagnostics.flush()

    await diagnostics.clearOldLogs(olderThan: 7, now: utcDate(year: 2026, month: 6, day: 21))

    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("perception/2026-06-01").path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("perception/2026-06-20").path))
}

private func makeEvent(
    id: String = "tick-1",
    timestamp: Date = utcDate(year: 2026, month: 6, day: 21)
) -> PerceptionDiagnosticEvent {
    PerceptionDiagnosticEvent(
        id: id,
        timestamp: timestamp,
        traceId: "trace-1",
        spanId: "span-perception-1",
        parentSpanId: nil,
        mode: .normal,
        featureFlags: PerceptionFeatureFlags(),
        snapshot: ContextSnapshotHarnessDTO(
            id: "snapshot-1",
            timestamp: timestamp,
            appName: "Safari",
            windowTitles: ["NBA Finals Live"],
            idleDuration: 2.1,
            recentInputActive: true,
            attentionState: .observing,
            regionHash: RegionHashDTO(
                globalDistance: 18,
                regionDistances: [.bottomRight: 45],
                changedRegions: [.bottomRight]
            ),
            screenshotRef: "screenshots/tick-1.jpg",
            isDynamicContent: true,
            contentType: .sports
        ),
        coWatchingSnapshot: nil,
        decision: GateDecision(
            kind: .analyze,
            reasons: ["region bottomRight changed"],
            triggeredSignals: [.regionHashChanged],
            fallbacks: []
        ),
        latency: PerceptionLatency(idleMs: 0, frontAppMs: 2, captureMs: 12, hashMs: 1, gateMs: 0, totalMs: 18),
        powerState: PowerState(batteryLevel: 0.9, isCharging: true, isLowPowerMode: false),
        thermalState: "nominal",
        petActions: [PetActionDTO(type: .setExpression, payload: ["expression": "curious"])],
        errors: []
    )
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AIspiritMacDiagnosticsTests-\(UUID().uuidString)", isDirectory: true)
}

private func utcDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    return components.date!
}

