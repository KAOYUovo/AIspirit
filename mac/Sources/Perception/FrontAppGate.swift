import Foundation

public struct FrontAppGateResult: Equatable, Sendable {
    public var snapshot: FrontAppSnapshot
    public var decision: GateDecision?
    public var shouldBlockCapture: Bool
    public var privacyMatch: PrivacyBlockMatch?
    public var errors: [DiagnosticErrorDTO]

    public init(
        snapshot: FrontAppSnapshot,
        decision: GateDecision?,
        shouldBlockCapture: Bool,
        privacyMatch: PrivacyBlockMatch?,
        errors: [DiagnosticErrorDTO]
    ) {
        self.snapshot = snapshot
        self.decision = decision
        self.shouldBlockCapture = shouldBlockCapture
        self.privacyMatch = privacyMatch
        self.errors = errors
    }
}

public struct FrontAppGate: Sendable {
    private let detector: any FrontAppDetecting
    private let blocklist: PrivacyBlocklist

    public init(detector: any FrontAppDetecting, blocklist: PrivacyBlocklist = .defaults) {
        self.detector = detector
        self.blocklist = blocklist
    }

    public func evaluate(previousSnapshot: FrontAppSnapshot? = nil) async -> FrontAppGateResult {
        do {
            return Self.evaluate(
                snapshot: try await detector.detect(),
                previousSnapshot: previousSnapshot,
                blocklist: blocklist
            )
        } catch {
            return FrontAppGateResult(
                snapshot: .unknown,
                decision: nil,
                shouldBlockCapture: false,
                privacyMatch: nil,
                errors: [
                    DiagnosticErrorDTO(
                        module: "perception.frontApp",
                        code: "front_app_detector_unavailable",
                        message: String(describing: error),
                        isFallbackApplied: true
                    )
                ]
            )
        }
    }

    public static func evaluate(
        snapshot: FrontAppSnapshot,
        previousSnapshot: FrontAppSnapshot? = nil,
        blocklist: PrivacyBlocklist = .defaults
    ) -> FrontAppGateResult {
        if let match = blocklist.match(snapshot) {
            return FrontAppGateResult(
                snapshot: snapshot,
                decision: GateDecision(
                    kind: .skipPrivacyBlocked,
                    reasons: ["privacy blocklist matched \(match.field.rawValue)"],
                    triggeredSignals: [],
                    fallbacks: []
                ),
                shouldBlockCapture: true,
                privacyMatch: match,
                errors: []
            )
        }

        let signals = triggerSignals(snapshot: snapshot, previousSnapshot: previousSnapshot)
        guard signals.isEmpty == false else {
            return FrontAppGateResult(
                snapshot: snapshot,
                decision: nil,
                shouldBlockCapture: false,
                privacyMatch: nil,
                errors: []
            )
        }

        return FrontAppGateResult(
            snapshot: snapshot,
            decision: GateDecision(
                kind: .analyze,
                reasons: ["front app context changed"],
                triggeredSignals: signals,
                fallbacks: []
            ),
            shouldBlockCapture: false,
            privacyMatch: nil,
            errors: []
        )
    }

    private static func triggerSignals(
        snapshot: FrontAppSnapshot,
        previousSnapshot: FrontAppSnapshot?
    ) -> [TriggerSignal] {
        guard let previousSnapshot else {
            return []
        }

        var signals: [TriggerSignal] = []
        if snapshot.bundleIdentifier != previousSnapshot.bundleIdentifier
            || snapshot.appName != previousSnapshot.appName {
            signals.append(.appChanged)
        }

        if Set(snapshot.windowTitles) != Set(previousSnapshot.windowTitles) {
            signals.append(.windowTitleChanged)
        }

        return signals
    }
}
