import Foundation
import Perception

public struct MockIdleDetector: IdleDetecting {
    public var idleDuration: TimeInterval
    public var error: CollectorFailure?

    public init(idleDuration: TimeInterval = 0, error: CollectorFailure? = nil) {
        self.idleDuration = idleDuration
        self.error = error
    }

    public func secondsSinceLastInput() async throws -> TimeInterval {
        if let error {
            throw error
        }
        return idleDuration
    }
}

public struct MockFrontAppDetector: FrontAppDetecting {
    public var snapshot: FrontAppSnapshot
    public var error: CollectorFailure?

    public init(snapshot: FrontAppSnapshot = .unknown, error: CollectorFailure? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    public func detect() async throws -> FrontAppSnapshot {
        if let error {
            throw error
        }
        return snapshot
    }
}

public actor MockScreenCapture: ScreenCapturing {
    public var frames: [CapturedFrame]
    public var error: CollectorFailure?

    public init(frames: [CapturedFrame] = [], error: CollectorFailure? = nil) {
        self.frames = frames
        self.error = error
    }

    public func capture() async throws -> CapturedFrame {
        if let error {
            throw error
        }
        guard !frames.isEmpty else {
            throw CollectorFailure.captureFailed("mock frame queue is empty")
        }
        return frames.removeFirst()
    }
}

public actor MockScreenStream: ScreenStreaming {
    public private(set) var didStart = false
    public private(set) var didStop = false
    public var frames: [CapturedFrame]
    public var startError: CollectorFailure?

    public init(frames: [CapturedFrame] = [], startError: CollectorFailure? = nil) {
        self.frames = frames
        self.startError = startError
    }

    public func start() async throws {
        if let startError {
            throw startError
        }
        didStart = true
    }

    public func stop() async {
        didStop = true
    }

    public func nextFrame() async throws -> CapturedFrame? {
        guard !frames.isEmpty else {
            return nil
        }
        return frames.removeFirst()
    }
}

public struct MockScreenStateMonitor: ScreenStateMonitoring {
    public var state: ScreenState
    public var error: CollectorFailure?

    public init(state: ScreenState = .active, error: CollectorFailure? = nil) {
        self.state = state
        self.error = error
    }

    public func currentState() async throws -> ScreenState {
        if let error {
            throw error
        }
        return state
    }
}

public struct MockPowerMonitor: PowerMonitoring {
    public var snapshot: PowerSnapshot
    public var error: CollectorFailure?

    public init(snapshot: PowerSnapshot = .nominal, error: CollectorFailure? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    public func currentPowerSnapshot() async throws -> PowerSnapshot {
        if let error {
            throw error
        }
        return snapshot
    }
}

public struct MockOCRTextRecognizer: OCRTextRecognizing {
    public var text: [String]
    public var error: CollectorFailure?

    public init(text: [String] = [], error: CollectorFailure? = nil) {
        self.text = text
        self.error = error
    }

    public func recognizeText(in frame: CapturedFrame) async throws -> [String] {
        if let error {
            throw error
        }
        return text
    }
}

public actor MockSystemAudioCapture: SystemAudioCapturing {
    public private(set) var didStart = false
    public private(set) var didStop = false
    public var chunks: [AudioChunk]
    public var startError: CollectorFailure?

    public init(chunks: [AudioChunk] = [], startError: CollectorFailure? = nil) {
        self.chunks = chunks
        self.startError = startError
    }

    public func start() async throws {
        if let startError {
            throw startError
        }
        didStart = true
    }

    public func stop() async {
        didStop = true
    }

    public func nextAudioChunk() async throws -> AudioChunk? {
        guard !chunks.isEmpty else {
            return nil
        }
        return chunks.removeFirst()
    }
}

public struct MockWhisperTranscriber: WhisperTranscribing {
    public var transcript: TranscriptSegment
    public var error: CollectorFailure?

    public init(transcript: TranscriptSegment = TranscriptSegment(text: ""), error: CollectorFailure? = nil) {
        self.transcript = transcript
        self.error = error
    }

    public func transcribe(_ chunk: AudioChunk) async throws -> TranscriptSegment {
        if let error {
            throw error
        }
        return transcript
    }
}

public struct MockWebMetadataSearch: WebMetadataSearching {
    public var result: WebMetadataResult?
    public var error: CollectorFailure?

    public init(result: WebMetadataResult? = nil, error: CollectorFailure? = nil) {
        self.result = result
        self.error = error
    }

    public func searchMetadata(query: String) async throws -> WebMetadataResult? {
        if let error {
            throw error
        }
        return result
    }
}

public actor MockVLMAnalyzer: VLMAnalyzing {
    private var results: [Result<VLMAnalysisResult, Error>]
    private let suspendsUntilReleased: Bool
    private var remainingSuspensions: Int
    private let delayNanoseconds: UInt64
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var storage: [VLMAnalysisRequest] = []

    public init(
        results: [Result<VLMAnalysisResult, Error>] = [.success(VLMAnalysisResult())],
        suspendsUntilReleased: Bool = false,
        suspensionCount: Int = .max,
        delayNanoseconds: UInt64 = 0
    ) {
        self.results = results
        self.suspendsUntilReleased = suspendsUntilReleased
        self.remainingSuspensions = suspensionCount
        self.delayNanoseconds = delayNanoseconds
    }

    public var invocations: [VLMAnalysisRequest] {
        storage
    }

    public func analyze(_ request: VLMAnalysisRequest) async throws -> VLMAnalysisResult {
        storage.append(request)

        if suspendsUntilReleased && remainingSuspensions > 0 {
            remainingSuspensions -= 1
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
            }
        }

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        guard results.isEmpty == false else {
            return VLMAnalysisResult()
        }

        switch results.removeFirst() {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    public func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
