import Foundation

public struct WhisperTranscriptionResult: Equatable, Sendable {
    public var transcript: String?
    public var segments: [TranscriptSegment]
    public var didRun: Bool
    public var errors: [DiagnosticErrorDTO]
    public var latency: PerceptionLatency

    public init(
        transcript: String?,
        segments: [TranscriptSegment],
        didRun: Bool,
        errors: [DiagnosticErrorDTO],
        latency: PerceptionLatency
    ) {
        self.transcript = transcript
        self.segments = segments
        self.didRun = didRun
        self.errors = errors
        self.latency = latency
    }
}

public struct WhisperTranscriptionGate: Sendable {
    private let transcriber: any WhisperTranscribing
    private let featureFlags: PerceptionFeatureFlags

    public init(
        transcriber: any WhisperTranscribing,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags()
    ) {
        self.transcriber = transcriber
        self.featureFlags = featureFlags
    }

    public func transcribe(_ chunks: [AudioChunk]) async -> WhisperTranscriptionResult {
        guard featureFlags.whisperTranscription else {
            return WhisperTranscriptionResult(
                transcript: nil,
                segments: [],
                didRun: false,
                errors: [],
                latency: PerceptionLatency(whisperMs: 0, totalMs: 0)
            )
        }

        let start = Date()
        var segments: [TranscriptSegment] = []
        var errors: [DiagnosticErrorDTO] = []

        for chunk in chunks {
            do {
                segments.append(try await transcriber.transcribe(chunk))
            } catch {
                errors.append(
                    DiagnosticErrorDTO(
                        module: "perception",
                        code: "whisper_transcription_failed",
                        message: String(describing: error),
                        isFallbackApplied: true
                    )
                )
                break
            }
        }

        let latencyMs = max(0, Int(Date().timeIntervalSince(start) * 1000))
        let transcript = segments.map(\.text).filter { $0.isEmpty == false }.joined(separator: " ")
        return WhisperTranscriptionResult(
            transcript: transcript.isEmpty ? nil : transcript,
            segments: segments,
            didRun: true,
            errors: errors,
            latency: PerceptionLatency(whisperMs: latencyMs, totalMs: latencyMs)
        )
    }
}
