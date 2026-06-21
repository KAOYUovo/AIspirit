import Foundation
import Testing
import Perception

@Test func snapshotAssemblerBuildsNormalContextSnapshot() {
    let timestamp = Date(timeIntervalSince1970: 1_790_000_000)
    let hash = RegionHashDTO(
        globalDistance: 11,
        regionDistances: [.center: 9],
        changedRegions: [.center]
    )
    let assembler = SnapshotAssembler(mode: .normal)

    let result = assembler.assemble(
        context: ContextSnapshotAssemblyInput(
            timestamp: timestamp,
            appName: "Xcode",
            windowTitles: ["SnapshotAssembler.swift"],
            idleDuration: 4,
            recentInputActive: true,
            attentionState: .observing,
            regionHash: hash,
            screenshotRef: "screenshots/tick-1.jpg",
            isDynamicContent: false,
            contentType: .coding
        )
    )

    #expect(result.mode == .normal)
    #expect(result.contextSnapshot?.appName == "Xcode")
    #expect(result.contextSnapshot?.windowTitles == ["SnapshotAssembler.swift"])
    #expect(result.contextSnapshot?.idleDuration == 4)
    #expect(result.contextSnapshot?.recentInputActive == true)
    #expect(result.contextSnapshot?.attentionState == .observing)
    #expect(result.contextSnapshot?.regionHash == hash)
    #expect(result.contextSnapshot?.screenshotRef == "screenshots/tick-1.jpg")
    #expect(result.contextSnapshot?.contentType == .coding)
    #expect(result.coWatchingSnapshot == nil)
    #expect(result.blockedCapabilities.isEmpty)
}

@Test func snapshotAssemblerBuildsCoWatchingSnapshotWhenProfileAllowsIt() {
    let timestamp = Date(timeIntervalSince1970: 1_790_000_100)
    var flags = PerceptionFeatureFlags()
    flags.coWatchingStream = true
    flags.keyframeExtraction = true
    flags.ocrRecognition = true
    flags.systemAudioCapture = true
    flags.whisperTranscription = true
    flags.webMetadataSearch = true
    let assembler = SnapshotAssembler(mode: .coWatching, flags: flags)

    let result = assembler.assemble(
        coWatching: CoWatchingSnapshotAssemblyInput(
            timestampStart: timestamp,
            timestampEnd: timestamp.addingTimeInterval(8),
            appName: "Safari",
            windowTitles: ["Warriors Live"],
            keyframeRefs: ["keyframes/1.jpg", "keyframes/2.jpg"],
            ocrText: ["GSW 102 LAL 99"],
            audioTranscript: "final minute",
            contentType: .sports,
            recentSummary: "close basketball game"
        )
    )

    #expect(result.mode == .coWatching)
    #expect(result.contextSnapshot == nil)
    #expect(result.coWatchingSnapshot?.appName == "Safari")
    #expect(result.coWatchingSnapshot?.keyframeRefs == ["keyframes/1.jpg", "keyframes/2.jpg"])
    #expect(result.coWatchingSnapshot?.ocrText == ["GSW 102 LAL 99"])
    #expect(result.coWatchingSnapshot?.audioTranscript == "final minute")
    #expect(result.coWatchingSnapshot?.contentType == .sports)
    #expect(result.coWatchingSnapshot?.recentSummary == "close basketball game")
    #expect(result.blockedCapabilities.isEmpty)
}

@Test func normalProfileBlocksCoWatchingSnapshotEvenWhenHighCostFlagsAreEnabled() {
    let timestamp = Date(timeIntervalSince1970: 1_790_000_200)
    let assembler = SnapshotAssembler(mode: .normal, flags: allHighCostFlagsEnabled())

    let result = assembler.assemble(
        context: ContextSnapshotAssemblyInput(
            timestamp: timestamp,
            appName: "Safari",
            windowTitles: ["Document"],
            idleDuration: 1,
            recentInputActive: false,
            attentionState: .busy,
            regionHash: nil,
            screenshotRef: "screenshots/tick-2.jpg",
            isDynamicContent: true,
            contentType: .office
        ),
        coWatching: CoWatchingSnapshotAssemblyInput(
            timestampStart: timestamp,
            timestampEnd: timestamp.addingTimeInterval(5),
            appName: "Safari",
            windowTitles: ["Document"],
            keyframeRefs: ["keyframes/forbidden.jpg"],
            ocrText: ["private doc"],
            audioTranscript: "spoken content",
            contentType: .office,
            recentSummary: "summary"
        )
    )

    #expect(result.mode == .normal)
    #expect(result.contextSnapshot != nil)
    #expect(result.coWatchingSnapshot == nil)
    #expect(!result.profile.useStreamCapture)
    #expect(!result.profile.useKeyframeExtraction)
    #expect(!result.profile.useAudioCapture)
    #expect(!result.profile.useWhisper)
    #expect(!result.profile.useWebSearch)
    #expect(result.blockedCapabilities.contains(.coWatchingSnapshot))
    #expect(result.blockedCapabilities.contains(.streamCapture))
    #expect(result.blockedCapabilities.contains(.keyframeExtraction))
    #expect(result.blockedCapabilities.contains(.audioCapture))
    #expect(result.blockedCapabilities.contains(.whisper))
    #expect(result.blockedCapabilities.contains(.webSearch))
}

@Test func lowPowerAndPausedProfilesBlockHighCostSnapshots() {
    let timestamp = Date(timeIntervalSince1970: 1_790_000_300)
    let coWatching = CoWatchingSnapshotAssemblyInput(
        timestampStart: timestamp,
        timestampEnd: timestamp.addingTimeInterval(5),
        appName: "TV",
        windowTitles: ["Live"],
        keyframeRefs: ["keyframes/1.jpg"],
        ocrText: ["score"],
        audioTranscript: "commentary",
        contentType: .sports,
        recentSummary: nil
    )

    let lowPower = SnapshotAssembler(mode: .lowPower, flags: allHighCostFlagsEnabled()).assemble(coWatching: coWatching)
    #expect(lowPower.mode == .lowPower)
    #expect(lowPower.coWatchingSnapshot == nil)
    #expect(lowPower.blockedCapabilities.contains(.coWatchingSnapshot))
    #expect(lowPower.blockedCapabilities.contains(.ocr))
    #expect(lowPower.blockedCapabilities.contains(.audioCapture))

    let paused = SnapshotAssembler(mode: .paused, flags: allHighCostFlagsEnabled()).assemble(coWatching: coWatching)
    #expect(paused.mode == .paused)
    #expect(paused.contextSnapshot == nil)
    #expect(paused.coWatchingSnapshot == nil)
    #expect(paused.blockedCapabilities.contains(.coWatchingSnapshot))
}

private func allHighCostFlagsEnabled() -> PerceptionFeatureFlags {
    PerceptionFeatureFlags(
        coWatchingStream: true,
        keyframeExtraction: true,
        ocrRecognition: true,
        systemAudioCapture: true,
        whisperTranscription: true,
        webMetadataSearch: true
    )
}
