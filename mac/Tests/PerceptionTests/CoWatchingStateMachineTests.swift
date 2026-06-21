import Foundation
import Testing
import Perception

@Test func coWatchingDoesNotEnterBeforeSustainWindow() {
    let machine = CoWatchingStateMachine(parameters: PerceptionParameters(coWatchEnterSustain: 5))
    let start = Date(timeIntervalSince1970: 1_780_010_000)

    let first = machine.evaluate(eligibleInput(at: start))
    let second = machine.evaluate(eligibleInput(at: start.addingTimeInterval(4), previous: first.state))

    #expect(first.state.mode == .normal)
    #expect(second.state.mode == .normal)
    #expect(second.petActions.isEmpty)
    #expect(second.diagnosticEvent.decision.kind == .skipStable)
}

@Test func coWatchingEntersAfterDynamicLargeVideoSustains() {
    let machine = CoWatchingStateMachine(parameters: PerceptionParameters(coWatchEnterSustain: 5))
    let start = Date(timeIntervalSince1970: 1_780_010_100)

    let first = machine.evaluate(eligibleInput(at: start, traceId: "trace-co-watch"))
    let entered = machine.evaluate(
        eligibleInput(
            at: start.addingTimeInterval(5),
            traceId: "trace-co-watch",
            previous: first.state
        )
    )

    #expect(entered.state.mode == .coWatching)
    #expect(entered.petActions == [
        PetActionDTO(type: .enterCoWatching, payload: ["reason": "dynamicLargeVideoSustained"])
    ])
    #expect(entered.diagnosticEvent.traceId == "trace-co-watch")
    #expect(entered.diagnosticEvent.mode == .coWatching)
    #expect(entered.diagnosticEvent.petActions == entered.petActions)
    #expect(entered.diagnosticEvent.decision.triggeredSignals == [.dynamicContent])
}

@Test func coWatchingAcceptsFullScreenAsLargeEnough() {
    let machine = CoWatchingStateMachine(parameters: PerceptionParameters(coWatchEnterSustain: 1))
    let start = Date(timeIntervalSince1970: 1_780_010_200)

    let first = machine.evaluate(eligibleInput(at: start, windowPresentation: .fullScreen))
    let entered = machine.evaluate(
        eligibleInput(
            at: start.addingTimeInterval(1),
            previous: first.state,
            windowPresentation: .fullScreen
        )
    )

    #expect(entered.state.mode == .coWatching)
}

@Test func coWatchingRequiresVideoLikeAppDynamicChangeAndLargeWindow() {
    let machine = CoWatchingStateMachine(parameters: PerceptionParameters(coWatchEnterSustain: 0))
    let now = Date(timeIntervalSince1970: 1_780_010_300)

    let nonVideo = machine.evaluate(eligibleInput(at: now, isVideoLikeApp: false))
    let staticFrame = machine.evaluate(eligibleInput(at: now, hasDynamicVisualChange: false))
    let smallWindow = machine.evaluate(eligibleInput(at: now, windowPresentation: .small))

    #expect(nonVideo.state.mode == .normal)
    #expect(staticFrame.state.mode == .normal)
    #expect(smallWindow.state.mode == .normal)
    #expect(nonVideo.petActions.isEmpty)
    #expect(staticFrame.petActions.isEmpty)
    #expect(smallWindow.petActions.isEmpty)
}

@Test func coWatchingKeepsModeDuringBriefPauseUntilExitSustain() {
    let machine = CoWatchingStateMachine(parameters: PerceptionParameters(coWatchExitSustain: 10))
    let start = Date(timeIntervalSince1970: 1_780_010_400)
    let current = CoWatchingState(mode: .coWatching, dynamicEligibleSince: start)

    let paused = machine.evaluate(
        eligibleInput(
            at: start.addingTimeInterval(4),
            previous: current,
            hasDynamicVisualChange: false
        )
    )

    #expect(paused.state.mode == .coWatching)
    #expect(paused.state.exitEligibleSince == start.addingTimeInterval(4))
    #expect(paused.petActions.isEmpty)
}

@Test func coWatchingExitsAfterExitConditionsSustain() {
    let machine = CoWatchingStateMachine(parameters: PerceptionParameters(coWatchExitSustain: 10))
    let start = Date(timeIntervalSince1970: 1_780_010_500)
    let current = CoWatchingState(
        mode: .coWatching,
        dynamicEligibleSince: start,
        exitEligibleSince: start
    )

    let exited = machine.evaluate(
        eligibleInput(
            at: start.addingTimeInterval(10),
            previous: current,
            hasDynamicVisualChange: false
        )
    )

    #expect(exited.state.mode == .normal)
    #expect(exited.petActions == [
        PetActionDTO(type: .exitCoWatching, payload: ["reason": "exitConditionsSustained"])
    ])
    #expect(exited.diagnosticEvent.mode == .normal)
    #expect(exited.diagnosticEvent.petActions == exited.petActions)
}

@Test func coWatchingManualExitIsImmediate() {
    let machine = CoWatchingStateMachine(parameters: PerceptionParameters(coWatchExitSustain: 10))
    let now = Date(timeIntervalSince1970: 1_780_010_600)
    let current = CoWatchingState(mode: .coWatching, dynamicEligibleSince: now)

    let exited = machine.evaluate(
        eligibleInput(at: now, previous: current, userRequestedExit: true)
    )

    #expect(exited.state.mode == .normal)
    #expect(exited.petActions == [
        PetActionDTO(type: .exitCoWatching, payload: ["reason": "userRequestedExit"])
    ])
}

private func eligibleInput(
    at timestamp: Date,
    traceId: String = "trace-co-watch",
    previous: CoWatchingState = .normal,
    isVideoLikeApp: Bool = true,
    hasDynamicVisualChange: Bool = true,
    windowPresentation: CoWatchingWindowPresentation = .large,
    userRequestedExit: Bool = false
) -> CoWatchingStateInput {
    CoWatchingStateInput(
        timestamp: timestamp,
        traceId: traceId,
        frontAppSnapshot: FrontAppSnapshot(appName: "Safari", windowTitles: ["Match highlights"]),
        previousState: previous,
        isVideoLikeApp: isVideoLikeApp,
        hasDynamicVisualChange: hasDynamicVisualChange,
        windowPresentation: windowPresentation,
        userRequestedExit: userRequestedExit
    )
}
