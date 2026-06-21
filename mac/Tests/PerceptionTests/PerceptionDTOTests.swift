import Foundation
import Testing
import Perception

@Test func featureFlagsDefaultValuesMatchPerceptionDesign() throws {
    let flags = PerceptionFeatureFlags()

    #expect(flags.singleFrameCapture)
    #expect(flags.regionDHash)
    #expect(flags.multiSignalTrigger)
    #expect(flags.attentionStateMachine)
    #expect(flags.screenStateMonitor)
    #expect(!flags.coWatchingStream)
    #expect(!flags.keyframeExtraction)
    #expect(!flags.ocrRecognition)
    #expect(!flags.systemAudioCapture)
    #expect(!flags.whisperTranscription)
    #expect(!flags.webMetadataSearch)

    try assertRoundTrip(flags)
}

@Test func parametersDefaultValuesMatchPerceptionDesign() throws {
    let parameters = PerceptionParameters.defaults

    #expect(parameters.normalTickInterval == 4)
    #expect(parameters.normalMinAIInterval == 15)
    #expect(parameters.coWatchingMinAIInterval == 10)
    #expect(parameters.lowPowerTickInterval == 12)
    #expect(parameters.lowPowerMinAIInterval == 60)
    #expect(parameters.forceRefreshInterval == 120)
    #expect(parameters.idleThreshold == 60)
    #expect(parameters.inputActiveWindow == 30)
    #expect(parameters.instantInputThreshold == 5)
    #expect(parameters.dHashGlobalThreshold == 10)
    #expect(parameters.dHashRegionThreshold == 8)
    #expect(parameters.coWatchEnterSustain == 5)
    #expect(parameters.coWatchExitSustain == 10)
    #expect(parameters.engagedTimeout == 30)
    #expect(parameters.thermalTrigger == .serious)
    #expect(parameters.batteryLevelTrigger == 0.2)
    #expect(parameters.vlmTimeout == 20)
    #expect(parameters.vlmMaxPerHour == 120)
    #expect(parameters.imageMaxEdge == 1536)
    #expect(parameters.imageJPEGQuality == 0.6)

    try assertRoundTrip(parameters)
}

@Test func profileDefaultsKeepHighCostCapabilitiesIsolated() throws {
    let defaultFlags = PerceptionFeatureFlags()
    let normal = PerceptionProfile.make(mode: .normal, flags: defaultFlags)

    #expect(normal.tickInterval == 4)
    #expect(normal.minAIInterval == 15)
    #expect(normal.useSingleFrameCapture)
    #expect(!normal.useStreamCapture)
    #expect(!normal.useKeyframeExtraction)
    #expect(!normal.useOCR)
    #expect(!normal.useAudioCapture)
    #expect(!normal.useWhisper)
    #expect(!normal.useWebSearch)

    let enabledFlags = PerceptionFeatureFlags(
        coWatchingStream: true,
        keyframeExtraction: true,
        ocrRecognition: true,
        systemAudioCapture: true,
        whisperTranscription: true,
        webMetadataSearch: true
    )

    let coWatching = PerceptionProfile.make(mode: .coWatching, flags: enabledFlags)
    #expect(coWatching.useStreamCapture)
    #expect(coWatching.minAIInterval == 10)
    #expect(coWatching.useKeyframeExtraction)
    #expect(coWatching.useOCR)
    #expect(coWatching.useAudioCapture)
    #expect(coWatching.useWhisper)
    #expect(coWatching.useWebSearch)

    let lowPower = PerceptionProfile.make(mode: .lowPower, flags: enabledFlags)
    #expect(lowPower.tickInterval == 12)
    #expect(lowPower.minAIInterval == 60)
    #expect(!lowPower.useStreamCapture)
    #expect(!lowPower.useOCR)
    #expect(!lowPower.useAudioCapture)
    #expect(!lowPower.useWhisper)

    let paused = PerceptionProfile.make(mode: .paused, flags: enabledFlags)
    #expect(paused.tickInterval == nil)
    #expect(paused.minAIInterval == nil)
    #expect(!paused.useSingleFrameCapture)
    #expect(!paused.useStreamCapture)
    #expect(!paused.useOCR)

    try assertRoundTrip(normal)
    try assertRoundTrip(coWatching)
    try assertRoundTrip(lowPower)
    try assertRoundTrip(paused)
}

@Test func profileIntervalsUseInjectedParameters() {
    let parameters = PerceptionParameters(
        normalTickInterval: 6,
        normalMinAIInterval: 18,
        coWatchingMinAIInterval: 7,
        lowPowerTickInterval: 14,
        lowPowerMinAIInterval: 75
    )

    let normal = PerceptionProfile.make(mode: .normal, parameters: parameters)
    let coWatching = PerceptionProfile.make(mode: .coWatching, parameters: parameters)
    let lowPower = PerceptionProfile.make(mode: .lowPower, parameters: parameters)

    #expect(normal.tickInterval == 6)
    #expect(normal.minAIInterval == 18)
    #expect(coWatching.minAIInterval == 7)
    #expect(lowPower.tickInterval == 14)
    #expect(lowPower.minAIInterval == 75)
}

@Test func harnessDTOsRoundTripThroughJSON() throws {
    let timestamp = Date(timeIntervalSince1970: 1_780_000_000)
    let hash = RegionHashDTO(
        globalDistance: 12,
        regionDistances: [.center: 3, .bottomRight: 9],
        changedRegions: [.bottomRight]
    )

    let snapshot = ContextSnapshotHarnessDTO(
        id: "snapshot-1",
        timestamp: timestamp,
        appName: "Safari",
        windowTitles: ["NBA Finals Live"],
        idleDuration: 2.1,
        recentInputActive: true,
        attentionState: .observing,
        regionHash: hash,
        screenshotRef: "screenshots/tick-1.jpg",
        isDynamicContent: true,
        contentType: .sports
    )

    let coWatching = CoWatchingSnapshotHarnessDTO(
        id: "cowatch-1",
        timestampStart: timestamp,
        timestampEnd: timestamp.addingTimeInterval(5),
        appName: "Safari",
        windowTitles: ["NBA Finals Live"],
        keyframeRefs: ["keyframes/1.jpg", "keyframes/2.jpg"],
        ocrText: ["LAL 98 BOS 96"],
        audioTranscript: "final possession",
        contentType: .sports,
        recentSummary: "close basketball game"
    )

    let decision = GateDecision(
        kind: .analyze,
        reasons: ["region bottomRight changed"],
        triggeredSignals: [.regionHashChanged],
        fallbacks: []
    )
    let action = PetActionDTO(type: .setExpression, payload: ["expression": "curious"])

    try assertRoundTrip(snapshot)
    try assertRoundTrip(coWatching)
    try assertRoundTrip(hash)
    try assertRoundTrip(decision)
    try assertRoundTrip(action)
}

@Test func regionHashUsesInjectedThresholds() {
    let hash = RegionHashDTO(
        globalDistance: 9,
        regionDistances: [.center: 7],
        changedRegions: []
    )

    #expect(!hash.hasSignificantChange(parameters: .defaults))

    let tuned = PerceptionParameters(dHashGlobalThreshold: 9, dHashRegionThreshold: 7)
    #expect(hash.hasSignificantChange(parameters: tuned))
}

private func assertRoundTrip<T: Codable & Equatable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(T.self, from: data)

    #expect(decoded == value)
}
