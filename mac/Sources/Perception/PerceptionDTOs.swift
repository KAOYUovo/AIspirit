import Foundation

public struct ContextSnapshotHarnessDTO: Codable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var appName: String
    public var windowTitles: [String]
    public var idleDuration: TimeInterval
    public var recentInputActive: Bool
    public var attentionState: AttentionState
    public var regionHash: RegionHashDTO?
    public var screenshotRef: String?
    public var isDynamicContent: Bool
    public var contentType: ContentType?

    public init(
        id: String,
        timestamp: Date,
        appName: String,
        windowTitles: [String],
        idleDuration: TimeInterval,
        recentInputActive: Bool,
        attentionState: AttentionState,
        regionHash: RegionHashDTO?,
        screenshotRef: String?,
        isDynamicContent: Bool,
        contentType: ContentType?
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitles = windowTitles
        self.idleDuration = idleDuration
        self.recentInputActive = recentInputActive
        self.attentionState = attentionState
        self.regionHash = regionHash
        self.screenshotRef = screenshotRef
        self.isDynamicContent = isDynamicContent
        self.contentType = contentType
    }
}

public struct CoWatchingSnapshotHarnessDTO: Codable, Equatable, Sendable {
    public var id: String
    public var timestampStart: Date
    public var timestampEnd: Date
    public var appName: String
    public var windowTitles: [String]
    public var keyframeRefs: [String]
    public var ocrText: [String]
    public var audioTranscript: String?
    public var contentType: ContentType
    public var recentSummary: String?

    public init(
        id: String,
        timestampStart: Date,
        timestampEnd: Date,
        appName: String,
        windowTitles: [String],
        keyframeRefs: [String],
        ocrText: [String],
        audioTranscript: String?,
        contentType: ContentType,
        recentSummary: String?
    ) {
        self.id = id
        self.timestampStart = timestampStart
        self.timestampEnd = timestampEnd
        self.appName = appName
        self.windowTitles = windowTitles
        self.keyframeRefs = keyframeRefs
        self.ocrText = ocrText
        self.audioTranscript = audioTranscript
        self.contentType = contentType
        self.recentSummary = recentSummary
    }
}

public struct RegionHashDTO: Codable, Equatable, Sendable {
    public var globalDistance: Int
    public var regionDistances: [ScreenRegion: Int]
    public var changedRegions: [ScreenRegion]

    public init(
        globalDistance: Int,
        regionDistances: [ScreenRegion: Int],
        changedRegions: [ScreenRegion]
    ) {
        self.globalDistance = globalDistance
        self.regionDistances = regionDistances
        self.changedRegions = changedRegions
    }

    public func hasSignificantChange(parameters: PerceptionParameters = .defaults) -> Bool {
        globalDistance >= parameters.dHashGlobalThreshold
            || regionDistances.values.contains { $0 >= parameters.dHashRegionThreshold }
    }
}

public struct GateDecision: Codable, Equatable, Sendable {
    public var kind: GateDecisionKind
    public var reasons: [String]
    public var triggeredSignals: [TriggerSignal]
    public var fallbacks: [String]

    public init(
        kind: GateDecisionKind,
        reasons: [String],
        triggeredSignals: [TriggerSignal],
        fallbacks: [String]
    ) {
        self.kind = kind
        self.reasons = reasons
        self.triggeredSignals = triggeredSignals
        self.fallbacks = fallbacks
    }
}

public struct PetActionDTO: Codable, Equatable, Sendable {
    public var type: PetActionType
    public var payload: [String: String]

    public init(type: PetActionType, payload: [String: String]) {
        self.type = type
        self.payload = payload
    }
}

