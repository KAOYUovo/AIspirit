import Foundation

public struct ScreenStreamCaptureResult: Equatable, Sendable {
    public var frames: [CapturedFrame]
    public var didStartStream: Bool
    public var didUseFallback: Bool
    public var decision: GateDecision?
    public var errors: [DiagnosticErrorDTO]

    public init(
        frames: [CapturedFrame],
        didStartStream: Bool,
        didUseFallback: Bool,
        decision: GateDecision?,
        errors: [DiagnosticErrorDTO]
    ) {
        self.frames = frames
        self.didStartStream = didStartStream
        self.didUseFallback = didUseFallback
        self.decision = decision
        self.errors = errors
    }
}

public struct ScreenStreamCaptureGate: Sendable {
    private let stream: any ScreenStreaming
    private let singleFrameCapturer: any ScreenCapturing
    private let featureFlags: PerceptionFeatureFlags
    private let fallbackFrameCount: Int

    public init(
        stream: any ScreenStreaming,
        singleFrameCapturer: any ScreenCapturing,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        fallbackFrameCount: Int = 3
    ) {
        self.stream = stream
        self.singleFrameCapturer = singleFrameCapturer
        self.featureFlags = featureFlags
        self.fallbackFrameCount = fallbackFrameCount
    }

    public func captureFrames() async -> ScreenStreamCaptureResult {
        guard featureFlags.coWatchingStream else {
            return ScreenStreamCaptureResult(
                frames: [],
                didStartStream: false,
                didUseFallback: false,
                decision: GateDecision(
                    kind: .skipStable,
                    reasons: ["co-watching stream disabled by feature flag"],
                    triggeredSignals: [],
                    fallbacks: []
                ),
                errors: []
            )
        }

        do {
            try await stream.start()
            var frames: [CapturedFrame] = []
            while let frame = try await stream.nextFrame() {
                frames.append(frame)
            }
            await stream.stop()
            return ScreenStreamCaptureResult(
                frames: frames,
                didStartStream: true,
                didUseFallback: false,
                decision: nil,
                errors: []
            )
        } catch {
            await stream.stop()
            let fallback = await captureFallbackFrames()
            return ScreenStreamCaptureResult(
                frames: fallback.frames,
                didStartStream: false,
                didUseFallback: true,
                decision: GateDecision(
                    kind: .fallback,
                    reasons: ["screen stream unavailable"],
                    triggeredSignals: [.dynamicContent],
                    fallbacks: ["multi-frame single screenshot capture"]
                ),
                errors: [streamError(from: error)] + fallback.errors
            )
        }
    }

    private func captureFallbackFrames() async -> (frames: [CapturedFrame], errors: [DiagnosticErrorDTO]) {
        var frames: [CapturedFrame] = []
        var errors: [DiagnosticErrorDTO] = []

        for _ in 0..<max(0, fallbackFrameCount) {
            do {
                frames.append(try await singleFrameCapturer.capture())
            } catch {
                errors.append(singleFrameError(from: error))
                break
            }
        }

        return (frames, errors)
    }

    private func streamError(from error: Error) -> DiagnosticErrorDTO {
        DiagnosticErrorDTO(
            module: "perception",
            code: "screen_stream_unavailable",
            message: String(describing: error),
            isFallbackApplied: true
        )
    }

    private func singleFrameError(from error: Error) -> DiagnosticErrorDTO {
        DiagnosticErrorDTO(
            module: "perception",
            code: "screen_stream_fallback_capture_failed",
            message: String(describing: error),
            isFallbackApplied: true
        )
    }
}
