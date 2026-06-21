import Foundation
import Testing
import Perception
import DebugTools

@Test func screenStateGatePausesBeforeCaptureForLockedOrSleepingStates() async {
    let timestamp = Date(timeIntervalSince1970: 1_780_000_100)

    let locked = await ScreenStateGate(monitor: MockScreenStateMonitor(state: .locked)).evaluate(timestamp: timestamp)
    #expect(locked.shouldPauseScheduler)
    #expect(locked.mode == .paused)
    #expect(locked.decision?.kind == .pausedScreenLocked)
    #expect(locked.decision?.reasons == ["screen locked"])

    let screenSleeping = ScreenStateGate.evaluate(screenState: .screenSleeping, timestamp: timestamp)
    #expect(screenSleeping.shouldPauseScheduler)
    #expect(screenSleeping.mode == .paused)
    #expect(screenSleeping.decision?.kind == .pausedScreenSleeping)

    let systemSleeping = ScreenStateGate.evaluate(screenState: .systemSleeping, timestamp: timestamp)
    #expect(systemSleeping.shouldPauseScheduler)
    #expect(systemSleeping.mode == .paused)
    #expect(systemSleeping.decision?.kind == .pausedSystemSleeping)
}

@Test func screenStateGateAllowsActiveAndUnknownStatesToContinue() async {
    let active = await ScreenStateGate(monitor: MockScreenStateMonitor(state: .active)).evaluate()
    #expect(active.shouldPauseScheduler == false)
    #expect(active.mode == .normal)
    #expect(active.decision == nil)

    let unknown = ScreenStateGate.evaluate(screenState: .unknown)
    #expect(unknown.shouldPauseScheduler == false)
    #expect(unknown.mode == .normal)
    #expect(unknown.decision == nil)
}

@Test func screenStateGateFallsBackToContinueWhenMonitorFails() async {
    let gate = ScreenStateGate(monitor: MockScreenStateMonitor(error: .unavailable("screen state")))

    let result = await gate.evaluate()

    #expect(result.screenState == .unknown)
    #expect(result.shouldPauseScheduler == false)
    #expect(result.decision == nil)
}

@Test func screenStateMonitorCanExposeInitialStateWithoutObservers() async throws {
    let monitor = ScreenStateMonitor(initialState: .screenSleeping, observeNotifications: false)

    #expect(try await monitor.currentState() == .screenSleeping)
}
