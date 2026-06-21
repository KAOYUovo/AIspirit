import Foundation
import Testing
import Perception

@Test func inMemoryLoggerCapturesRecordsForAssertions() {
    let logger = InMemoryLogger()

    logger.log(
        .info,
        "tick analyzed",
        module: "perception",
        traceId: "trace-1",
        metadata: ["region": "bottomRight"]
    )

    #expect(logger.records == [
        LogRecord(
            level: .info,
            message: "tick analyzed",
            module: "perception",
            traceId: "trace-1",
            metadata: ["region": "bottomRight"]
        )
    ])

    logger.clear()
    #expect(logger.records.isEmpty)
}

@Test func logLevelOrderingMatchesSeverity() {
    #expect(LogLevel.debug < .info)
    #expect(LogLevel.info < .warning)
    #expect(LogLevel.warning < .error)
}

@Test func fileLoggerWritesHumanReadableLinesAndFiltersByLevel() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }

    let timestamp = utcDate(year: 2026, month: 6, day: 21, hour: 1, minute: 2, second: 3)
    let logger = FileLogger(
        rootDirectory: root,
        minimumLevel: .info,
        clock: { timestamp }
    )

    logger.log(.debug, "hidden debug", module: "perception", traceId: "trace-hidden")
    logger.log(
        .info,
        "tick analyzed",
        module: "perception",
        traceId: "trace-1",
        metadata: ["idle": "2.1", "region": "bottomRight"]
    )
    await logger.flush()

    let fileURL = root.appendingPathComponent("2026-06-21/app.log")
    let contents = try String(contentsOf: fileURL, encoding: .utf8)

    #expect(!contents.contains("hidden debug"))
    #expect(contents.contains("[INFO ] [perception] [trace-1] tick analyzed"))
    #expect(contents.contains("idle=2.1 region=bottomRight"))
    #expect(await logger.failureCount == 0)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AIspiritMacTests-\(UUID().uuidString)", isDirectory: true)
}

private func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
    var components = DateComponents()
    components.calendar = Calendar(identifier: .gregorian)
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    return components.date!
}
