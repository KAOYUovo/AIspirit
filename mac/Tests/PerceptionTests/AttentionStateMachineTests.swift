import Foundation
import Testing
import Perception
import DebugTools

@Test func attentionStateMachineMatchesRequiredFixtures() {
    let machine = AttentionStateMachine()

    for fixture in AttentionStateFixtureFactory.requiredCases() {
        let result = machine.evaluate(input(from: fixture))

        #expect(result.state == fixture.expectedState, "fixture \(fixture.id)")
        #expect(result.petActions == fixture.expectedPetActions, "fixture \(fixture.id)")
    }
}

@Test func attentionStateMachineUsesInjectedEngagedTimeout() {
    let machine = AttentionStateMachine(parameters: PerceptionParameters(engagedTimeout: 45))
    let input = AttentionStateInput(
        previousState: .engaged,
        inputActivity: InputActivityState(
            timestamp: Date(timeIntervalSince1970: 1_780_020_000),
            recentInputActive: false,
            activeEventCount: 0,
            latestActiveTimestamp: nil
        ),
        secondsSinceEngaged: 40
    )

    #expect(machine.evaluate(input).state == .engaged)
}

@Test func attentionStateMachineUsesInjectedBusyThreshold() {
    let machine = AttentionStateMachine(busyInputEventThreshold: 4)
    let input = AttentionStateInput(
        inputActivity: InputActivityState(
            timestamp: Date(timeIntervalSince1970: 1_780_020_000),
            recentInputActive: true,
            activeEventCount: 3,
            latestActiveTimestamp: Date(timeIntervalSince1970: 1_780_020_000)
        )
    )

    #expect(machine.evaluate(input).state == .observing)
}

private func input(from fixture: AttentionStateFixtureCase) -> AttentionStateInput {
    AttentionStateInput(
        previousState: fixture.previousState,
        inputActivity: fixture.inputActivity,
        eventKind: fixture.eventKind,
        secondsSinceEngaged: fixture.secondsSinceEngaged,
        intendedPetAction: fixture.intendedPetAction
    )
}
