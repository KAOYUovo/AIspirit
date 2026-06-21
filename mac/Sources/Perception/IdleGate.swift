import Foundation

public struct IdleGateResult: Equatable, Sendable {
    public var idleDuration: TimeInterval
    public var mode: PerceptionMode
    public var decision: GateDecision?
    public var shouldSkipCapture: Bool
    public var errors: [DiagnosticErrorDTO]

    public init(
        idleDuration: TimeInterval,
        mode: PerceptionMode,
        decision: GateDecision?,
        shouldSkipCapture: Bool,
        errors: [DiagnosticErrorDTO]
    ) {
        self.idleDuration = idleDuration
        self.mode = mode
        self.decision = decision
        self.shouldSkipCapture = shouldSkipCapture
        self.errors = errors
    }
}

public struct IdleGate: Sendable {
    private let detector: any IdleDetecting
    private let parameters: PerceptionParameters

    public init(detector: any IdleDetecting, parameters: PerceptionParameters = .defaults) {
        self.detector = detector
        self.parameters = parameters
    }

    public func evaluate() async -> IdleGateResult {
        do {
            return Self.evaluate(idleDuration: try await detector.secondsSinceLastInput(), parameters: parameters)
        } catch {
            return IdleGateResult(
                idleDuration: 0,
                mode: .normal,
                decision: nil,
                shouldSkipCapture: false,
                errors: [
                    DiagnosticErrorDTO(
                        module: "perception.idle",
                        code: "idle_detector_unavailable",
                        message: String(describing: error),
                        isFallbackApplied: true
                    )
                ]
            )
        }
    }

    public static func evaluate(
        idleDuration: TimeInterval,
        parameters: PerceptionParameters = .defaults
    ) -> IdleGateResult {
        guard idleDuration > parameters.idleThreshold else {
            return IdleGateResult(
                idleDuration: idleDuration,
                mode: .normal,
                decision: nil,
                shouldSkipCapture: false,
                errors: []
            )
        }

        return IdleGateResult(
            idleDuration: idleDuration,
            mode: .normal,
            decision: GateDecision(
                kind: .skipIdle,
                reasons: ["idle above threshold"],
                triggeredSignals: [],
                fallbacks: []
            ),
            shouldSkipCapture: true,
            errors: []
        )
    }
}
