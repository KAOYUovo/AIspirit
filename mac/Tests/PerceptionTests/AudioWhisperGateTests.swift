import Foundation
import Testing
import Perception
import DebugTools

@Test func audioGateDoesNotStartCaptureWhenFlagIsDisabled() async {
    let capture = MockSystemAudioCapture(chunks: [audioChunk("audio-1")])
    var flags = PerceptionFeatureFlags()
    flags.systemAudioCapture = false

    let result = await SystemAudioCaptureGate(capture: capture, featureFlags: flags).captureChunks()

    #expect(result.didRun == false)
    #expect(result.chunks.isEmpty)
    #expect(await capture.didStart == false)
    #expect(result.errors.isEmpty)
}

@Test func audioGateReturnsChunksWhenFlagIsEnabled() async {
    let chunks = [audioChunk("audio-1"), audioChunk("audio-2")]
    let capture = MockSystemAudioCapture(chunks: chunks)
    var flags = PerceptionFeatureFlags()
    flags.systemAudioCapture = true

    let result = await SystemAudioCaptureGate(capture: capture, featureFlags: flags).captureChunks()

    #expect(result.didRun)
    #expect(result.chunks == chunks)
    #expect(await capture.didStart)
    #expect(await capture.didStop)
    #expect(result.errors.isEmpty)
    #expect(result.latency.audioMs != nil)
}

@Test func audioGateFallsBackToNoAudioWhenCaptureFails() async {
    let capture = MockSystemAudioCapture(startError: .permissionDenied("audio denied"))
    var flags = PerceptionFeatureFlags()
    flags.systemAudioCapture = true

    let result = await SystemAudioCaptureGate(capture: capture, featureFlags: flags).captureChunks()

    #expect(result.didRun)
    #expect(result.chunks.isEmpty)
    #expect(await capture.didStop)
    #expect(result.errors.count == 1)
    #expect(result.errors[0].code == "system_audio_capture_failed")
    #expect(result.errors[0].isFallbackApplied)
}

@Test func whisperGateDoesNotTranscribeWhenFlagIsDisabled() async {
    var flags = PerceptionFeatureFlags()
    flags.whisperTranscription = false

    let result = await WhisperTranscriptionGate(
        transcriber: MockWhisperTranscriber(transcript: TranscriptSegment(text: "hello")),
        featureFlags: flags
    ).transcribe([audioChunk("audio-1")])

    #expect(result.didRun == false)
    #expect(result.transcript == nil)
    #expect(result.segments.isEmpty)
    #expect(result.errors.isEmpty)
}

@Test func whisperGateCombinesTranscriptSegmentsWhenEnabled() async {
    var flags = PerceptionFeatureFlags()
    flags.whisperTranscription = true

    let result = await WhisperTranscriptionGate(
        transcriber: MockWhisperTranscriber(transcript: TranscriptSegment(text: "final possession")),
        featureFlags: flags
    ).transcribe([audioChunk("audio-1"), audioChunk("audio-2")])

    #expect(result.didRun)
    #expect(result.transcript == "final possession final possession")
    #expect(result.segments.count == 2)
    #expect(result.errors.isEmpty)
    #expect(result.latency.whisperMs != nil)
}

@Test func whisperGateFallsBackToNoTranscriptWhenTranscriptionFails() async {
    var flags = PerceptionFeatureFlags()
    flags.whisperTranscription = true

    let result = await WhisperTranscriptionGate(
        transcriber: MockWhisperTranscriber(error: .transcriptionFailed("no model")),
        featureFlags: flags
    ).transcribe([audioChunk("audio-1")])

    #expect(result.didRun)
    #expect(result.transcript == nil)
    #expect(result.segments.isEmpty)
    #expect(result.errors.count == 1)
    #expect(result.errors[0].code == "whisper_transcription_failed")
    #expect(result.errors[0].isFallbackApplied)
}

@Test func whisperTranscriberReportsUnavailableWhenNoLocalBackendIsConfigured() async {
    await #expect(throws: CollectorFailure.self) {
        _ = try await WhisperTranscriber().transcribe(audioChunk("audio-1"))
    }
}

private func audioChunk(_ id: String) -> AudioChunk {
    let start = Date(timeIntervalSince1970: 1_780_050_000)
    return AudioChunk(
        id: id,
        timestampStart: start,
        timestampEnd: start.addingTimeInterval(5),
        sampleRate: 16_000,
        channelCount: 1,
        pcmData: Data([1, 2, 3, 4])
    )
}
