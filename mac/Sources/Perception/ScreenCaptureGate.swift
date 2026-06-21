import Foundation

public struct ScreenCaptureGateResult: Equatable, Sendable {
    public var frame: CapturedFrame?
    public var decision: GateDecision?
    public var shouldSkipFrame: Bool
    public var errors: [DiagnosticErrorDTO]

    public init(
        frame: CapturedFrame?,
        decision: GateDecision?,
        shouldSkipFrame: Bool,
        errors: [DiagnosticErrorDTO]
    ) {
        self.frame = frame
        self.decision = decision
        self.shouldSkipFrame = shouldSkipFrame
        self.errors = errors
    }
}

public struct ScreenCaptureGate: Sendable {
    private let capturer: any ScreenCapturing

    public init(capturer: any ScreenCapturing) {
        self.capturer = capturer
    }

    public func captureFrame() async -> ScreenCaptureGateResult {
        do {
            return ScreenCaptureGateResult(
                frame: try await capturer.capture(),
                decision: nil,
                shouldSkipFrame: false,
                errors: []
            )
        } catch {
            return Self.failureResult(error: error)
        }
    }

    public static func failureResult(error: Error) -> ScreenCaptureGateResult {
        ScreenCaptureGateResult(
            frame: nil,
            decision: GateDecision(
                kind: .skipNoScreen,
                reasons: ["screen capture failed"],
                triggeredSignals: [],
                fallbacks: ["skip current frame"]
            ),
            shouldSkipFrame: true,
            errors: [
                DiagnosticErrorDTO(
                    module: "perception.screenCapture",
                    code: errorCode(for: error),
                    message: String(describing: error),
                    isFallbackApplied: true
                )
            ]
        )
    }

    private static func errorCode(for error: Error) -> String {
        guard let failure = error as? CollectorFailure else {
            return "screen_capture_failed"
        }

        switch failure {
        case .permissionDenied:
            return "screen_capture_permission_denied"
        case .captureFailed:
            return "screen_capture_failed"
        default:
            return "screen_capture_unavailable"
        }
    }
}
