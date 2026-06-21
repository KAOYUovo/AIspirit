import Foundation

public enum SnapshotCapability: String, Codable, CaseIterable, Equatable, Sendable {
    case singleFrameCapture
    case streamCapture
    case keyframeExtraction
    case ocr
    case audioCapture
    case whisper
    case webSearch
    case coWatchingSnapshot
}

public struct ContextSnapshotAssemblyInput: Equatable, Sendable {
    public var id: String?
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
        id: String? = nil,
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

public struct CoWatchingSnapshotAssemblyInput: Equatable, Sendable {
    public var id: String?
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
        id: String? = nil,
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

public struct SnapshotAssemblyResult: Equatable, Sendable {
    public var mode: PerceptionMode
    public var profile: PerceptionProfile
    public var contextSnapshot: ContextSnapshotHarnessDTO?
    public var coWatchingSnapshot: CoWatchingSnapshotHarnessDTO?
    public var blockedCapabilities: [SnapshotCapability]

    public init(
        mode: PerceptionMode,
        profile: PerceptionProfile,
        contextSnapshot: ContextSnapshotHarnessDTO?,
        coWatchingSnapshot: CoWatchingSnapshotHarnessDTO?,
        blockedCapabilities: [SnapshotCapability]
    ) {
        self.mode = mode
        self.profile = profile
        self.contextSnapshot = contextSnapshot
        self.coWatchingSnapshot = coWatchingSnapshot
        self.blockedCapabilities = blockedCapabilities
    }
}

public struct SnapshotAssembler: Sendable {
    private let profile: PerceptionProfile

    public init(
        mode: PerceptionMode,
        flags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        parameters: PerceptionParameters = .defaults
    ) {
        self.profile = PerceptionProfile.make(mode: mode, flags: flags, parameters: parameters)
    }

    public init(profile: PerceptionProfile) {
        self.profile = profile
    }

    public func assemble(
        context: ContextSnapshotAssemblyInput? = nil,
        coWatching: CoWatchingSnapshotAssemblyInput? = nil
    ) -> SnapshotAssemblyResult {
        let contextSnapshot = makeContextSnapshot(from: context)
        let coWatchingSnapshot = makeCoWatchingSnapshot(from: coWatching)
        let blocked = blockedCapabilities(
            hasContextInput: context != nil,
            hasCoWatchingInput: coWatching != nil,
            emittedContext: contextSnapshot != nil,
            emittedCoWatching: coWatchingSnapshot != nil
        )

        return SnapshotAssemblyResult(
            mode: profile.mode,
            profile: profile,
            contextSnapshot: contextSnapshot,
            coWatchingSnapshot: coWatchingSnapshot,
            blockedCapabilities: blocked
        )
    }

    private func makeContextSnapshot(from input: ContextSnapshotAssemblyInput?) -> ContextSnapshotHarnessDTO? {
        guard let input, profile.useSingleFrameCapture else {
            return nil
        }

        return ContextSnapshotHarnessDTO(
            id: input.id ?? UUID().uuidString,
            timestamp: input.timestamp,
            appName: input.appName,
            windowTitles: input.windowTitles,
            idleDuration: input.idleDuration,
            recentInputActive: input.recentInputActive,
            attentionState: input.attentionState,
            regionHash: input.regionHash,
            screenshotRef: input.screenshotRef,
            isDynamicContent: input.isDynamicContent,
            contentType: input.contentType
        )
    }

    private func makeCoWatchingSnapshot(from input: CoWatchingSnapshotAssemblyInput?) -> CoWatchingSnapshotHarnessDTO? {
        guard let input, profile.mode == .coWatching else {
            return nil
        }

        return CoWatchingSnapshotHarnessDTO(
            id: input.id ?? UUID().uuidString,
            timestampStart: input.timestampStart,
            timestampEnd: input.timestampEnd,
            appName: input.appName,
            windowTitles: input.windowTitles,
            keyframeRefs: profile.useKeyframeExtraction ? input.keyframeRefs : [],
            ocrText: profile.useOCR ? input.ocrText : [],
            audioTranscript: profile.useAudioCapture && profile.useWhisper ? input.audioTranscript : nil,
            contentType: input.contentType,
            recentSummary: profile.useWebSearch ? input.recentSummary : nil
        )
    }

    private func blockedCapabilities(
        hasContextInput: Bool,
        hasCoWatchingInput: Bool,
        emittedContext: Bool,
        emittedCoWatching: Bool
    ) -> [SnapshotCapability] {
        var blocked: [SnapshotCapability] = []

        if hasContextInput && emittedContext == false {
            append(.singleFrameCapture, to: &blocked)
        }
        if hasCoWatchingInput && emittedCoWatching == false {
            append(.coWatchingSnapshot, to: &blocked)
        }
        guard hasCoWatchingInput else {
            return blocked
        }

        if profile.useStreamCapture == false {
            append(.streamCapture, to: &blocked)
        }
        if profile.useKeyframeExtraction == false {
            append(.keyframeExtraction, to: &blocked)
        }
        if profile.useOCR == false {
            append(.ocr, to: &blocked)
        }
        if profile.useAudioCapture == false {
            append(.audioCapture, to: &blocked)
        }
        if profile.useWhisper == false {
            append(.whisper, to: &blocked)
        }
        if profile.useWebSearch == false {
            append(.webSearch, to: &blocked)
        }

        return blocked
    }

    private func append(_ capability: SnapshotCapability, to capabilities: inout [SnapshotCapability]) {
        guard capabilities.contains(capability) == false else {
            return
        }
        capabilities.append(capability)
    }
}
