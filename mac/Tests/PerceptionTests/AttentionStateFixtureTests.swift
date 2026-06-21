import Foundation
import Testing
import Perception
import DebugTools

@Test func attentionStateFixturesCoverHarnessRequiredCases() {
    let cases = AttentionStateFixtureFactory.requiredCases()

    #expect(cases.map(\.id) == [
        "high-recent-input-busy",
        "low-input-stable-observing",
        "user-invoked-engaged",
        "engaged-timeout-observing",
        "busy-suppresses-long-bubble"
    ])
    #expect(cases.map(\.expectedState) == [
        .busy,
        .observing,
        .engaged,
        .observing,
        .busy
    ])
}

@Test func attentionStateFixturesDeclarePetActionSuppression() {
    let cases = Dictionary(uniqueKeysWithValues: AttentionStateFixtureFactory.requiredCases().map { ($0.id, $0) })
    let suppression = cases["busy-suppresses-long-bubble"]?.expectedPetActions.first

    #expect(suppression?.type == .suppressBubble)
    #expect(suppression?.payload["reason"] == "attentionState=busy")
}

@Test func attentionStateFixturesRoundTripThroughJSON() throws {
    let cases = AttentionStateFixtureFactory.requiredCases()

    let data = try JSONEncoder().encode(cases)
    let decoded = try JSONDecoder().decode([AttentionStateFixtureCase].self, from: data)

    #expect(decoded == cases)
}
