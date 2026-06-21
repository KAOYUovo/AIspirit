public struct PerceptionFeatureFlags: Codable, Equatable, Sendable {
    public var singleFrameCapture: Bool
    public var regionDHash: Bool
    public var multiSignalTrigger: Bool
    public var attentionStateMachine: Bool
    public var screenStateMonitor: Bool
    public var coWatchingStream: Bool
    public var keyframeExtraction: Bool
    public var ocrRecognition: Bool
    public var systemAudioCapture: Bool
    public var whisperTranscription: Bool
    public var webMetadataSearch: Bool

    public init(
        singleFrameCapture: Bool = true,
        regionDHash: Bool = true,
        multiSignalTrigger: Bool = true,
        attentionStateMachine: Bool = true,
        screenStateMonitor: Bool = true,
        coWatchingStream: Bool = false,
        keyframeExtraction: Bool = false,
        ocrRecognition: Bool = false,
        systemAudioCapture: Bool = false,
        whisperTranscription: Bool = false,
        webMetadataSearch: Bool = false
    ) {
        self.singleFrameCapture = singleFrameCapture
        self.regionDHash = regionDHash
        self.multiSignalTrigger = multiSignalTrigger
        self.attentionStateMachine = attentionStateMachine
        self.screenStateMonitor = screenStateMonitor
        self.coWatchingStream = coWatchingStream
        self.keyframeExtraction = keyframeExtraction
        self.ocrRecognition = ocrRecognition
        self.systemAudioCapture = systemAudioCapture
        self.whisperTranscription = whisperTranscription
        self.webMetadataSearch = webMetadataSearch
    }
}

