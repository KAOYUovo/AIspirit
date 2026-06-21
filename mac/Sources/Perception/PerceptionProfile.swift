import Foundation

public struct PerceptionProfile: Codable, Equatable, Sendable {
    public var mode: PerceptionMode
    public var tickInterval: TimeInterval?
    public var minAIInterval: TimeInterval?
    public var useSingleFrameCapture: Bool
    public var useStreamCapture: Bool
    public var useKeyframeExtraction: Bool
    public var useOCR: Bool
    public var useAudioCapture: Bool
    public var useWhisper: Bool
    public var useWebSearch: Bool

    public init(
        mode: PerceptionMode,
        tickInterval: TimeInterval?,
        minAIInterval: TimeInterval?,
        useSingleFrameCapture: Bool,
        useStreamCapture: Bool,
        useKeyframeExtraction: Bool,
        useOCR: Bool,
        useAudioCapture: Bool,
        useWhisper: Bool,
        useWebSearch: Bool
    ) {
        self.mode = mode
        self.tickInterval = tickInterval
        self.minAIInterval = minAIInterval
        self.useSingleFrameCapture = useSingleFrameCapture
        self.useStreamCapture = useStreamCapture
        self.useKeyframeExtraction = useKeyframeExtraction
        self.useOCR = useOCR
        self.useAudioCapture = useAudioCapture
        self.useWhisper = useWhisper
        self.useWebSearch = useWebSearch
    }

    public static func make(
        mode: PerceptionMode,
        flags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        parameters: PerceptionParameters = .defaults
    ) -> PerceptionProfile {
        switch mode {
        case .normal:
            return PerceptionProfile(
                mode: mode,
                tickInterval: parameters.normalTickInterval,
                minAIInterval: parameters.normalMinAIInterval,
                useSingleFrameCapture: flags.singleFrameCapture,
                useStreamCapture: false,
                useKeyframeExtraction: false,
                useOCR: flags.ocrRecognition,
                useAudioCapture: false,
                useWhisper: false,
                useWebSearch: false
            )
        case .coWatching:
            return PerceptionProfile(
                mode: mode,
                tickInterval: nil,
                minAIInterval: parameters.coWatchingMinAIInterval,
                useSingleFrameCapture: flags.singleFrameCapture,
                useStreamCapture: flags.coWatchingStream,
                useKeyframeExtraction: flags.keyframeExtraction,
                useOCR: flags.ocrRecognition,
                useAudioCapture: flags.systemAudioCapture,
                useWhisper: flags.whisperTranscription,
                useWebSearch: flags.webMetadataSearch
            )
        case .lowPower:
            return PerceptionProfile(
                mode: mode,
                tickInterval: parameters.lowPowerTickInterval,
                minAIInterval: parameters.lowPowerMinAIInterval,
                useSingleFrameCapture: flags.singleFrameCapture,
                useStreamCapture: false,
                useKeyframeExtraction: false,
                useOCR: false,
                useAudioCapture: false,
                useWhisper: false,
                useWebSearch: false
            )
        case .paused:
            return PerceptionProfile(
                mode: mode,
                tickInterval: nil,
                minAIInterval: nil,
                useSingleFrameCapture: false,
                useStreamCapture: false,
                useKeyframeExtraction: false,
                useOCR: false,
                useAudioCapture: false,
                useWhisper: false,
                useWebSearch: false
            )
        }
    }
}
