import Foundation

public protocol IdleDetecting: Sendable {
    func secondsSinceLastInput() async throws -> TimeInterval
}

public protocol FrontAppDetecting: Sendable {
    func detect() async throws -> FrontAppSnapshot
}

public protocol ScreenCapturing: Sendable {
    func capture() async throws -> CapturedFrame
}

public protocol ScreenStreaming: Sendable {
    func start() async throws
    func stop() async
    func nextFrame() async throws -> CapturedFrame?
}

public protocol ScreenStateMonitoring: Sendable {
    func currentState() async throws -> ScreenState
}

public protocol PowerMonitoring: Sendable {
    func currentPowerSnapshot() async throws -> PowerSnapshot
}

public protocol OCRTextRecognizing: Sendable {
    func recognizeText(in frame: CapturedFrame) async throws -> [String]
}

public protocol SystemAudioCapturing: Sendable {
    func start() async throws
    func stop() async
    func nextAudioChunk() async throws -> AudioChunk?
}

public protocol WhisperTranscribing: Sendable {
    func transcribe(_ chunk: AudioChunk) async throws -> TranscriptSegment
}

public protocol WebMetadataSearching: Sendable {
    func searchMetadata(query: String) async throws -> WebMetadataResult?
}

