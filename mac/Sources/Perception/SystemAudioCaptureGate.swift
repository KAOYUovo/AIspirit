import Foundation

public struct SystemAudioCaptureResult: Equatable, Sendable {
    public var chunks: [AudioChunk]
    public var didRun: Bool
    public var errors: [DiagnosticErrorDTO]
    public var latency: PerceptionLatency

    public init(
        chunks: [AudioChunk],
        didRun: Bool,
        errors: [DiagnosticErrorDTO],
        latency: PerceptionLatency
    ) {
        self.chunks = chunks
        self.didRun = didRun
        self.errors = errors
        self.latency = latency
    }
}

public struct SystemAudioCaptureGate: Sendable {
    private let capture: any SystemAudioCapturing
    private let featureFlags: PerceptionFeatureFlags

    public init(
        capture: any SystemAudioCapturing,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags()
    ) {
        self.capture = capture
        self.featureFlags = featureFlags
    }

    public func captureChunks() async -> SystemAudioCaptureResult {
        guard featureFlags.systemAudioCapture else {
            return SystemAudioCaptureResult(
                chunks: [],
                didRun: false,
                errors: [],
                latency: PerceptionLatency(audioMs: 0, totalMs: 0)
            )
        }

        let start = Date()
        do {
            try await capture.start()
            var chunks: [AudioChunk] = []
            while let chunk = try await capture.nextAudioChunk() {
                chunks.append(chunk)
            }
            await capture.stop()
            let latencyMs = max(0, Int(Date().timeIntervalSince(start) * 1000))
            return SystemAudioCaptureResult(
                chunks: chunks,
                didRun: true,
                errors: [],
                latency: PerceptionLatency(audioMs: latencyMs, totalMs: latencyMs)
            )
        } catch {
            await capture.stop()
            let latencyMs = max(0, Int(Date().timeIntervalSince(start) * 1000))
            return SystemAudioCaptureResult(
                chunks: [],
                didRun: true,
                errors: [
                    DiagnosticErrorDTO(
                        module: "perception",
                        code: "system_audio_capture_failed",
                        message: String(describing: error),
                        isFallbackApplied: true
                    )
                ],
                latency: PerceptionLatency(audioMs: latencyMs, totalMs: latencyMs)
            )
        }
    }
}
