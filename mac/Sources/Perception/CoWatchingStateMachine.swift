import Foundation

public enum CoWatchingWindowPresentation: String, Codable, Equatable, Sendable {
    case small
    case large
    case fullScreen

    public var isLargeEnoughForCoWatching: Bool {
        self == .large || self == .fullScreen
    }
}

public struct CoWatchingState: Codable, Equatable, Sendable {
    public var mode: PerceptionMode
    public var dynamicEligibleSince: Date?
    public var exitEligibleSince: Date?

    public init(
        mode: PerceptionMode = .normal,
        dynamicEligibleSince: Date? = nil,
        exitEligibleSince: Date? = nil
    ) {
        self.mode = mode
        self.dynamicEligibleSince = dynamicEligibleSince
        self.exitEligibleSince = exitEligibleSince
    }

    public static let normal = CoWatchingState()
}

public struct CoWatchingStateInput: Equatable, Sendable {
    public var timestamp: Date
    public var traceId: String
    public var parentSpanId: String?
    public var featureFlags: PerceptionFeatureFlags
    public var frontAppSnapshot: FrontAppSnapshot
    public var previousState: CoWatchingState
    public var isVideoLikeApp: Bool
    public var hasDynamicVisualChange: Bool
    public var windowPresentation: CoWatchingWindowPresentation
    public var userRequestedExit: Bool

    public init(
        timestamp: Date = Date(),
        traceId: String = UUID().uuidString,
        parentSpanId: String? = nil,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        frontAppSnapshot: FrontAppSnapshot = .unknown,
        previousState: CoWatchingState = .normal,
        isVideoLikeApp: Bool = false,
        hasDynamicVisualChange: Bool = false,
        windowPresentation: CoWatchingWindowPresentation = .small,
        userRequestedExit: Bool = false
    ) {
        self.timestamp = timestamp
        self.traceId = traceId
        self.parentSpanId = parentSpanId
        self.featureFlags = featureFlags
        self.frontAppSnapshot = frontAppSnapshot
        self.previousState = previousState
        self.isVideoLikeApp = isVideoLikeApp
        self.hasDynamicVisualChange = hasDynamicVisualChange
        self.windowPresentation = windowPresentation
        self.userRequestedExit = userRequestedExit
    }
}

public struct CoWatchingStateMachineResult: Equatable, Sendable {
    public var state: CoWatchingState
    public var petActions: [PetActionDTO]
    public var diagnosticEvent: PerceptionDiagnosticEvent

    public init(
        state: CoWatchingState,
        petActions: [PetActionDTO],
        diagnosticEvent: PerceptionDiagnosticEvent
    ) {
        self.state = state
        self.petActions = petActions
        self.diagnosticEvent = diagnosticEvent
    }
}

public struct CoWatchingStateMachine: Sendable {
    private let parameters: PerceptionParameters

    public init(parameters: PerceptionParameters = .defaults) {
        self.parameters = parameters
    }

    public func evaluate(_ input: CoWatchingStateInput) -> CoWatchingStateMachineResult {
        let start = Date()
        let entryEligible = input.isVideoLikeApp
            && input.hasDynamicVisualChange
            && input.windowPresentation.isLargeEnoughForCoWatching

        if input.userRequestedExit {
            let state = CoWatchingState(mode: .normal)
            return result(
                state: state,
                petActions: [exitAction(reason: "userRequestedExit")],
                input: input,
                decision: decision(kind: .analyze, reasons: ["user requested co-watching exit"], signals: []),
                start: start
            )
        }

        switch input.previousState.mode {
        case .coWatching:
            return evaluateExit(input: input, entryEligible: entryEligible, start: start)
        default:
            return evaluateEntry(input: input, entryEligible: entryEligible, start: start)
        }
    }

    private func evaluateEntry(
        input: CoWatchingStateInput,
        entryEligible: Bool,
        start: Date
    ) -> CoWatchingStateMachineResult {
        guard entryEligible else {
            let state = CoWatchingState(mode: .normal)
            return result(
                state: state,
                petActions: [],
                input: input,
                decision: decision(kind: .skipStable, reasons: ["co-watching entry conditions not met"], signals: []),
                start: start
            )
        }

        let since = input.previousState.dynamicEligibleSince ?? input.timestamp
        let sustained = input.timestamp.timeIntervalSince(since)

        if sustained >= parameters.coWatchEnterSustain {
            let state = CoWatchingState(mode: .coWatching, dynamicEligibleSince: since, exitEligibleSince: nil)
            return result(
                state: state,
                petActions: [enterAction(reason: "dynamicLargeVideoSustained")],
                input: input,
                decision: decision(
                    kind: .analyze,
                    reasons: ["co-watching entry conditions sustained"],
                    signals: [.dynamicContent]
                ),
                start: start
            )
        }

        let state = CoWatchingState(mode: .normal, dynamicEligibleSince: since, exitEligibleSince: nil)
        return result(
            state: state,
            petActions: [],
            input: input,
            decision: decision(
                kind: .skipStable,
                reasons: ["co-watching entry hysteresis not satisfied"],
                signals: [.dynamicContent]
            ),
            start: start
        )
    }

    private func evaluateExit(
        input: CoWatchingStateInput,
        entryEligible: Bool,
        start: Date
    ) -> CoWatchingStateMachineResult {
        guard entryEligible == false else {
            let state = CoWatchingState(
                mode: .coWatching,
                dynamicEligibleSince: input.timestamp,
                exitEligibleSince: nil
            )
            return result(
                state: state,
                petActions: [],
                input: input,
                decision: decision(
                    kind: .analyze,
                    reasons: ["co-watching conditions still active"],
                    signals: [.dynamicContent]
                ),
                start: start
            )
        }

        let since = input.previousState.exitEligibleSince ?? input.timestamp
        let sustained = input.timestamp.timeIntervalSince(since)

        if sustained >= parameters.coWatchExitSustain {
            let state = CoWatchingState(mode: .normal)
            return result(
                state: state,
                petActions: [exitAction(reason: "exitConditionsSustained")],
                input: input,
                decision: decision(kind: .analyze, reasons: ["co-watching exit conditions sustained"], signals: []),
                start: start
            )
        }

        let state = CoWatchingState(
            mode: .coWatching,
            dynamicEligibleSince: input.previousState.dynamicEligibleSince,
            exitEligibleSince: since
        )
        return result(
            state: state,
            petActions: [],
            input: input,
            decision: decision(kind: .skipStable, reasons: ["co-watching exit hysteresis not satisfied"], signals: []),
            start: start
        )
    }

    private func enterAction(reason: String) -> PetActionDTO {
        PetActionDTO(type: .enterCoWatching, payload: ["reason": reason])
    }

    private func exitAction(reason: String) -> PetActionDTO {
        PetActionDTO(type: .exitCoWatching, payload: ["reason": reason])
    }

    private func decision(
        kind: GateDecisionKind,
        reasons: [String],
        signals: [TriggerSignal]
    ) -> GateDecision {
        GateDecision(kind: kind, reasons: reasons, triggeredSignals: signals, fallbacks: [])
    }

    private func result(
        state: CoWatchingState,
        petActions: [PetActionDTO],
        input: CoWatchingStateInput,
        decision: GateDecision,
        start: Date
    ) -> CoWatchingStateMachineResult {
        let latencyMs = max(0, Int(Date().timeIntervalSince(start) * 1000))
        let diagnosticEvent = PerceptionDiagnosticEvent(
            id: UUID().uuidString,
            timestamp: input.timestamp,
            traceId: input.traceId,
            spanId: UUID().uuidString,
            parentSpanId: input.parentSpanId,
            mode: state.mode,
            featureFlags: input.featureFlags,
            snapshot: ContextSnapshotHarnessDTO(
                id: UUID().uuidString,
                timestamp: input.timestamp,
                appName: input.frontAppSnapshot.appName,
                windowTitles: input.frontAppSnapshot.windowTitles,
                idleDuration: 0,
                recentInputActive: false,
                attentionState: .observing,
                regionHash: nil,
                screenshotRef: nil,
                isDynamicContent: input.hasDynamicVisualChange,
                contentType: nil
            ),
            coWatchingSnapshot: nil,
            decision: decision,
            latency: PerceptionLatency(totalMs: latencyMs),
            powerState: nil,
            thermalState: nil,
            petActions: petActions,
            errors: []
        )
        return CoWatchingStateMachineResult(
            state: state,
            petActions: petActions,
            diagnosticEvent: diagnosticEvent
        )
    }
}
