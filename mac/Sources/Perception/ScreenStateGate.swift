import Foundation

public struct ScreenStateGateResult: Equatable, Sendable {
    public var screenState: ScreenState
    public var mode: PerceptionMode
    public var decision: GateDecision?
    public var shouldPauseScheduler: Bool

    public init(
        screenState: ScreenState,
        mode: PerceptionMode,
        decision: GateDecision?,
        shouldPauseScheduler: Bool
    ) {
        self.screenState = screenState
        self.mode = mode
        self.decision = decision
        self.shouldPauseScheduler = shouldPauseScheduler
    }
}

public struct ScreenStateGate: Sendable {
    private let monitor: any ScreenStateMonitoring

    public init(monitor: any ScreenStateMonitoring) {
        self.monitor = monitor
    }

    public func evaluate(timestamp: Date = Date()) async -> ScreenStateGateResult {
        do {
            return Self.evaluate(screenState: try await monitor.currentState(), timestamp: timestamp)
        } catch {
            return Self.evaluate(screenState: .unknown, timestamp: timestamp)
        }
    }

    public static func evaluate(screenState: ScreenState, timestamp: Date = Date()) -> ScreenStateGateResult {
        switch screenState {
        case .locked:
            return pausedResult(
                screenState: screenState,
                kind: .pausedScreenLocked,
                reason: "screen locked",
                timestamp: timestamp
            )
        case .screenSleeping:
            return pausedResult(
                screenState: screenState,
                kind: .pausedScreenSleeping,
                reason: "screen sleeping",
                timestamp: timestamp
            )
        case .systemSleeping:
            return pausedResult(
                screenState: screenState,
                kind: .pausedSystemSleeping,
                reason: "system sleeping",
                timestamp: timestamp
            )
        case .active, .unknown:
            return ScreenStateGateResult(
                screenState: screenState,
                mode: .normal,
                decision: nil,
                shouldPauseScheduler: false
            )
        }
    }

    private static func pausedResult(
        screenState: ScreenState,
        kind: GateDecisionKind,
        reason: String,
        timestamp: Date
    ) -> ScreenStateGateResult {
        ScreenStateGateResult(
            screenState: screenState,
            mode: .paused,
            decision: GateDecision(
                kind: kind,
                reasons: [reason],
                triggeredSignals: [],
                fallbacks: []
            ),
            shouldPauseScheduler: true
        )
    }
}
