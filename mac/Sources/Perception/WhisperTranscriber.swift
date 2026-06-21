import Foundation

public struct WhisperTranscriber: WhisperTranscribing {
    public init() {}

    public func transcribe(_ chunk: AudioChunk) async throws -> TranscriptSegment {
        throw CollectorFailure.unavailable("Local Whisper backend is not configured")
    }
}
