import CoreGraphics
import Foundation
import ImageIO
import Perception

public struct LivePerceptionTickResult: Equatable, Sendable {
    public var event: PerceptionDiagnosticEvent
    public var frame: CapturedFrame?
    public var screenState: ScreenState
    public var powerSnapshot: PowerSnapshot
    public var frontAppSnapshot: FrontAppSnapshot
    public var regionHashSnapshot: RegionDHashSnapshot?
    public var captureSkipped: Bool

    public init(
        event: PerceptionDiagnosticEvent,
        frame: CapturedFrame?,
        screenState: ScreenState,
        powerSnapshot: PowerSnapshot,
        frontAppSnapshot: FrontAppSnapshot,
        regionHashSnapshot: RegionDHashSnapshot?,
        captureSkipped: Bool
    ) {
        self.event = event
        self.frame = frame
        self.screenState = screenState
        self.powerSnapshot = powerSnapshot
        self.frontAppSnapshot = frontAppSnapshot
        self.regionHashSnapshot = regionHashSnapshot
        self.captureSkipped = captureSkipped
    }
}

public actor LivePerceptionRunner {
    private let idleDetector: any IdleDetecting
    private let frontAppDetector: any FrontAppDetecting
    private let screenStateMonitor: any ScreenStateMonitoring
    private let powerMonitor: any PowerMonitoring
    private let screenCapture: any ScreenCapturing
    private let parameters: PerceptionParameters
    private let privacyBlocklist: PrivacyBlocklist
    private var inputActivityWindow: InputActivityWindow
    private var previousFrontAppSnapshot: FrontAppSnapshot?
    private var previousHashSnapshot: RegionDHashSnapshot?
    private var lastAnalysisAt: Date?
    private var lastAIAt: Date?

    public init(parameters: PerceptionParameters = .defaults) {
        self.init(
            idleDetector: CGEventSourceIdleDetector(),
            frontAppDetector: NSWorkspaceFrontAppDetector(),
            screenStateMonitor: ScreenStateMonitor(),
            powerMonitor: PowerMonitor(),
            screenCapture: ScreenCaptureKitCapturer(parameters: parameters),
            parameters: parameters
        )
    }

    public init(
        idleDetector: any IdleDetecting,
        frontAppDetector: any FrontAppDetecting,
        screenStateMonitor: any ScreenStateMonitoring,
        powerMonitor: any PowerMonitoring,
        screenCapture: any ScreenCapturing,
        parameters: PerceptionParameters = .defaults,
        privacyBlocklist: PrivacyBlocklist = .defaults
    ) {
        self.idleDetector = idleDetector
        self.frontAppDetector = frontAppDetector
        self.screenStateMonitor = screenStateMonitor
        self.powerMonitor = powerMonitor
        self.screenCapture = screenCapture
        self.parameters = parameters
        self.privacyBlocklist = privacyBlocklist
        self.inputActivityWindow = InputActivityWindow(parameters: parameters)
    }

    public func runTick(
        timestamp: Date = Date(),
        traceId: String = UUID().uuidString,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags()
    ) async -> LivePerceptionTickResult {
        let screenState = await ScreenStateGate(monitor: screenStateMonitor).evaluate(timestamp: timestamp)
        let power = await PowerThermalGate(monitor: powerMonitor, parameters: parameters).evaluate()
        let idle = await IdleGate(detector: idleDetector, parameters: parameters).evaluate()
        let frontApp = await FrontAppGate(
            detector: frontAppDetector,
            blocklist: privacyBlocklist
        ).evaluate(previousSnapshot: previousFrontAppSnapshot)
        let inputActivity = inputActivityWindow.record(timestamp: timestamp, idleDuration: idle.idleDuration)
        let baseInput = gateInput(
            timestamp: timestamp,
            traceId: traceId,
            featureFlags: featureFlags,
            screenState: screenState.screenState,
            powerSnapshot: power.snapshot,
            idleDuration: idle.idleDuration,
            frontAppSnapshot: frontApp.snapshot,
            recentInputActive: inputActivity.recentInputActive,
            regionHash: nil
        )
        let preCaptureGate = GateChain(parameters: parameters, privacyBlocklist: privacyBlocklist).evaluate(baseInput)
        let preCaptureErrors = idle.errors + frontApp.errors

        if shouldSkipBeforeCapture(preCaptureGate.decision.kind) {
            previousFrontAppSnapshot = frontApp.snapshot
            var event = preCaptureGate.diagnosticEvent
            event.errors.append(contentsOf: preCaptureErrors)
            return result(
                event: event,
                frame: nil,
                screenState: screenState.screenState,
                powerSnapshot: power.snapshot,
                frontAppSnapshot: frontApp.snapshot,
                regionHashSnapshot: nil,
                captureSkipped: true
            )
        }

        let captureStarted = Date()
        let capture = await ScreenCaptureGate(capturer: screenCapture).captureFrame()
        let captureMs = max(0, Int(Date().timeIntervalSince(captureStarted) * 1000))
        guard let frame = capture.frame else {
            previousFrontAppSnapshot = frontApp.snapshot
            var event = preCaptureGate.diagnosticEvent
            if let decision = capture.decision {
                event.decision = decision
            }
            event.latency.captureMs = captureMs
            event.latency.totalMs = (event.latency.totalMs ?? 0) + captureMs
            event.errors.append(contentsOf: preCaptureErrors + capture.errors)
            return result(
                event: event,
                frame: nil,
                screenState: screenState.screenState,
                powerSnapshot: power.snapshot,
                frontAppSnapshot: frontApp.snapshot,
                regionHashSnapshot: nil,
                captureSkipped: true
            )
        }

        let hashStarted = Date()
        let hashResult = computeHash(for: frame)
        let hashMs = max(0, Int(Date().timeIntervalSince(hashStarted) * 1000))
        let inputWithHash = gateInput(
            timestamp: timestamp,
            traceId: traceId,
            featureFlags: featureFlags,
            screenState: screenState.screenState,
            powerSnapshot: power.snapshot,
            idleDuration: idle.idleDuration,
            frontAppSnapshot: frontApp.snapshot,
            recentInputActive: inputActivity.recentInputActive,
            regionHash: hashResult.regionHash
        )
        let gateResult = GateChain(parameters: parameters, privacyBlocklist: privacyBlocklist).evaluate(inputWithHash)
        var event = gateResult.diagnosticEvent
        event.errors.append(contentsOf: preCaptureErrors + hashResult.errors)
        event.latency.captureMs = captureMs
        event.latency.hashMs = hashMs
        event.latency.totalMs = (event.latency.totalMs ?? 0) + captureMs + hashMs
        event.snapshot?.screenshotRef = "live:\(frame.id)"

        previousFrontAppSnapshot = frontApp.snapshot
        previousHashSnapshot = hashResult.snapshot ?? previousHashSnapshot
        if gateResult.shouldAnalyze {
            lastAnalysisAt = timestamp
            lastAIAt = timestamp
        }

        return result(
            event: event,
            frame: frame,
            screenState: screenState.screenState,
            powerSnapshot: power.snapshot,
            frontAppSnapshot: frontApp.snapshot,
            regionHashSnapshot: hashResult.snapshot,
            captureSkipped: false
        )
    }

    private func gateInput(
        timestamp: Date,
        traceId: String,
        featureFlags: PerceptionFeatureFlags,
        screenState: ScreenState,
        powerSnapshot: PowerSnapshot,
        idleDuration: TimeInterval,
        frontAppSnapshot: FrontAppSnapshot,
        recentInputActive: Bool,
        regionHash: RegionHashDTO?
    ) -> GateChainInput {
        GateChainInput(
            timestamp: timestamp,
            traceId: traceId,
            featureFlags: featureFlags,
            screenState: screenState,
            powerSnapshot: powerSnapshot,
            idleDuration: idleDuration,
            frontAppSnapshot: frontAppSnapshot,
            previousFrontAppSnapshot: previousFrontAppSnapshot,
            regionHash: regionHash,
            recentInputActive: recentInputActive,
            secondsSinceLastAnalysis: secondsSince(lastAnalysisAt, now: timestamp, defaultValue: parameters.forceRefreshInterval),
            secondsSinceLastAI: secondsSince(lastAIAt, now: timestamp, defaultValue: parameters.normalMinAIInterval),
            attentionState: recentInputActive ? .busy : .observing
        )
    }

    private func secondsSince(_ date: Date?, now: Date, defaultValue: TimeInterval) -> TimeInterval {
        guard let date else {
            return defaultValue
        }
        return max(0, now.timeIntervalSince(date))
    }

    private func shouldSkipBeforeCapture(_ kind: GateDecisionKind) -> Bool {
        switch kind {
        case .pausedScreenLocked, .pausedScreenSleeping, .pausedSystemSleeping, .lowPowerThrottled, .skipIdle, .skipPrivacyBlocked:
            return true
        default:
            return false
        }
    }

    private func computeHash(
        for frame: CapturedFrame
    ) -> (snapshot: RegionDHashSnapshot?, regionHash: RegionHashDTO?, errors: [DiagnosticErrorDTO]) {
        guard let image = cgImage(from: frame) else {
            return (
                nil,
                nil,
                [
                    DiagnosticErrorDTO(
                        module: "perception.live",
                        code: "live_frame_decode_failed",
                        message: "Captured frame did not contain decodable image data.",
                        isFallbackApplied: true
                    )
                ]
            )
        }

        do {
            let comparison = try RegionDHashComputer(parameters: parameters).compare(
                current: image,
                previous: previousHashSnapshot
            )
            return (comparison.current, comparison.regionHash, [])
        } catch {
            return (
                nil,
                nil,
                [
                    DiagnosticErrorDTO(
                        module: "perception.live",
                        code: "live_hash_failed",
                        message: String(describing: error),
                        isFallbackApplied: true
                    )
                ]
            )
        }
    }

    private func cgImage(from frame: CapturedFrame) -> CGImage? {
        guard
            let imageData = frame.imageData,
            let source = CGImageSourceCreateWithData(imageData as CFData, nil)
        else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func result(
        event: PerceptionDiagnosticEvent,
        frame: CapturedFrame?,
        screenState: ScreenState,
        powerSnapshot: PowerSnapshot,
        frontAppSnapshot: FrontAppSnapshot,
        regionHashSnapshot: RegionDHashSnapshot?,
        captureSkipped: Bool
    ) -> LivePerceptionTickResult {
        LivePerceptionTickResult(
            event: event,
            frame: frame,
            screenState: screenState,
            powerSnapshot: powerSnapshot,
            frontAppSnapshot: frontAppSnapshot,
            regionHashSnapshot: regionHashSnapshot,
            captureSkipped: captureSkipped
        )
    }
}
