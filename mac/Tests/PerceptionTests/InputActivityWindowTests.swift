import Foundation
import Testing
import Perception

@Test func inputActivityRecordsInstantInputWhenIdleIsBelowThreshold() {
    var window = InputActivityWindow(parameters: PerceptionParameters())
    let timestamp = Date(timeIntervalSince1970: 100)

    let state = window.record(timestamp: timestamp, idleDuration: 4.9)

    #expect(state.recentInputActive)
    #expect(state.activeEventCount == 1)
    #expect(state.latestActiveTimestamp == timestamp)
    #expect(window.recentActiveTimestamps == [timestamp])
}

@Test func inputActivityDoesNotRecordWhenIdleEqualsInstantThreshold() {
    var window = InputActivityWindow(parameters: PerceptionParameters())
    let timestamp = Date(timeIntervalSince1970: 100)

    let state = window.record(timestamp: timestamp, idleDuration: 5)

    #expect(!state.recentInputActive)
    #expect(state.activeEventCount == 0)
    #expect(window.recentActiveTimestamps.isEmpty)
}

@Test func inputActivityRemainsActiveWithinSlidingWindow() {
    var window = InputActivityWindow(parameters: PerceptionParameters())
    let start = Date(timeIntervalSince1970: 100)

    _ = window.record(timestamp: start, idleDuration: 1)
    let state = window.record(timestamp: start.addingTimeInterval(30), idleDuration: 12)

    #expect(state.recentInputActive)
    #expect(state.activeEventCount == 1)
    #expect(state.latestActiveTimestamp == start)
}

@Test func inputActivityExpiresAfterSlidingWindow() {
    var window = InputActivityWindow(parameters: PerceptionParameters())
    let start = Date(timeIntervalSince1970: 100)

    _ = window.record(timestamp: start, idleDuration: 1)
    let state = window.record(timestamp: start.addingTimeInterval(30.1), idleDuration: 12)

    #expect(!state.recentInputActive)
    #expect(state.activeEventCount == 0)
    #expect(window.recentActiveTimestamps.isEmpty)
}

@Test func inputActivityUsesInjectedParameters() {
    var window = InputActivityWindow(
        parameters: PerceptionParameters(
            inputActiveWindow: 10,
            instantInputThreshold: 2
        )
    )
    let start = Date(timeIntervalSince1970: 100)

    _ = window.record(timestamp: start, idleDuration: 1.9)
    let active = window.record(timestamp: start.addingTimeInterval(10), idleDuration: 3)
    let expired = window.record(timestamp: start.addingTimeInterval(10.1), idleDuration: 3)

    #expect(active.recentInputActive)
    #expect(!expired.recentInputActive)
}

@Test func inputActivityStateRoundTripsThroughJSON() throws {
    let state = InputActivityState(
        timestamp: Date(timeIntervalSince1970: 100),
        recentInputActive: true,
        activeEventCount: 2,
        latestActiveTimestamp: Date(timeIntervalSince1970: 90)
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(state)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(InputActivityState.self, from: data)

    #expect(decoded == state)
}

