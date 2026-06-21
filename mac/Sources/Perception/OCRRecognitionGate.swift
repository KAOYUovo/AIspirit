import Foundation

public struct OCRRecognitionResult: Equatable, Sendable {
    public var text: [String]
    public var didRun: Bool
    public var errors: [DiagnosticErrorDTO]
    public var latency: PerceptionLatency

    public init(
        text: [String],
        didRun: Bool,
        errors: [DiagnosticErrorDTO],
        latency: PerceptionLatency
    ) {
        self.text = text
        self.didRun = didRun
        self.errors = errors
        self.latency = latency
    }
}

public struct OCRRecognitionGate: Sendable {
    private let recognizer: any OCRTextRecognizing
    private let featureFlags: PerceptionFeatureFlags

    public init(
        recognizer: any OCRTextRecognizing,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags()
    ) {
        self.recognizer = recognizer
        self.featureFlags = featureFlags
    }

    public func recognizeText(in frame: CapturedFrame) async -> OCRRecognitionResult {
        guard featureFlags.ocrRecognition else {
            return OCRRecognitionResult(
                text: [],
                didRun: false,
                errors: [],
                latency: PerceptionLatency(ocrMs: 0, totalMs: 0)
            )
        }

        let start = Date()
        do {
            let text = try await recognizer.recognizeText(in: frame)
            let latencyMs = max(0, Int(Date().timeIntervalSince(start) * 1000))
            return OCRRecognitionResult(
                text: text,
                didRun: true,
                errors: [],
                latency: PerceptionLatency(ocrMs: latencyMs, totalMs: latencyMs)
            )
        } catch {
            let latencyMs = max(0, Int(Date().timeIntervalSince(start) * 1000))
            return OCRRecognitionResult(
                text: [],
                didRun: true,
                errors: [
                    DiagnosticErrorDTO(
                        module: "perception",
                        code: "ocr_failed",
                        message: String(describing: error),
                        isFallbackApplied: true
                    )
                ],
                latency: PerceptionLatency(ocrMs: latencyMs, totalMs: latencyMs)
            )
        }
    }
}
