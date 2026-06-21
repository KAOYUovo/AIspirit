import Foundation
import Testing
import Perception

@Test func keyframeExtractorDoesNotRunWhenFlagIsDisabled() {
    var flags = PerceptionFeatureFlags()
    flags.keyframeExtraction = false
    let extractor = KeyframeExtractor(
        featureFlags: flags,
        config: KeyframeExtractorConfig(sampleInterval: 1, retentionWindow: 10, maxKeyframes: 5)
    )

    let result = extractor.extract(from: [
        candidate("frame-0", timestamp: 0),
        candidate("frame-1", timestamp: 1)
    ])

    #expect(result.didRun == false)
    #expect(result.keyframes.isEmpty)
    #expect(result.diagnosticEvent == nil)
}

@Test func keyframeExtractorSamplesAtFixedIntervalWhenNoHashExists() {
    let extractor = enabledExtractor(sampleInterval: 1)

    let result = extractor.extract(from: [
        candidate("frame-0", timestamp: 0),
        candidate("frame-0.4", timestamp: 0.4),
        candidate("frame-1.0", timestamp: 1.0),
        candidate("frame-1.5", timestamp: 1.5),
        candidate("frame-2.1", timestamp: 2.1)
    ])

    #expect(result.keyframes.map(\.id) == ["frame-0", "frame-1.0", "frame-2.1"])
    #expect(result.decision.triggeredSignals == [.coWatchingKeyframe])
}

@Test func keyframeExtractorFiltersStableSampledFramesUsingRegionHash() {
    let extractor = enabledExtractor(sampleInterval: 1)

    let result = extractor.extract(from: [
        candidate("frame-0", timestamp: 0, regionHash: stableHash()),
        candidate("frame-1.0", timestamp: 1.0, regionHash: stableHash()),
        candidate("frame-2.0", timestamp: 2.0, regionHash: changedHash())
    ])

    #expect(result.keyframes.map(\.id) == ["frame-0", "frame-2.0"])
    #expect(result.decision.reasons.contains("region hash change selected keyframe"))
}

@Test func keyframeExtractorRetainsRecentRepresentativeFramesOnly() {
    let extractor = KeyframeExtractor(
        featureFlags: enabledFlags(),
        config: KeyframeExtractorConfig(sampleInterval: 1, retentionWindow: 3, maxKeyframes: 3)
    )

    let result = extractor.extract(from: [
        candidate("frame-0", timestamp: 0),
        candidate("frame-1", timestamp: 1),
        candidate("frame-2", timestamp: 2),
        candidate("frame-3", timestamp: 3),
        candidate("frame-4", timestamp: 4)
    ])

    #expect(result.keyframes.map(\.id) == ["frame-2", "frame-3", "frame-4"])
}

@Test func keyframeExtractorUsesInjectedHashThresholds() {
    let parameters = PerceptionParameters(dHashRegionThreshold: 12)
    let extractor = KeyframeExtractor(
        featureFlags: enabledFlags(),
        parameters: parameters,
        config: KeyframeExtractorConfig(sampleInterval: 1, retentionWindow: 10, maxKeyframes: 5)
    )

    let result = extractor.extract(from: [
        candidate("frame-0", timestamp: 0, regionHash: stableHash()),
        candidate("frame-1", timestamp: 1, regionHash: regionHash(centerDistance: 8)),
        candidate("frame-2", timestamp: 2, regionHash: regionHash(centerDistance: 12))
    ])

    #expect(result.keyframes.map(\.id) == ["frame-0", "frame-2"])
}

private func enabledExtractor(sampleInterval: TimeInterval) -> KeyframeExtractor {
    KeyframeExtractor(
        featureFlags: enabledFlags(),
        config: KeyframeExtractorConfig(sampleInterval: sampleInterval, retentionWindow: 10, maxKeyframes: 5)
    )
}

private func enabledFlags() -> PerceptionFeatureFlags {
    var flags = PerceptionFeatureFlags()
    flags.keyframeExtraction = true
    return flags
}

private func candidate(
    _ id: String,
    timestamp: TimeInterval,
    regionHash: RegionHashDTO? = nil
) -> KeyframeCandidate {
    KeyframeCandidate(
        frame: CapturedFrame(
            id: id,
            timestamp: Date(timeIntervalSince1970: 1_780_030_000 + timestamp),
            width: 1920,
            height: 1080,
            displayID: 1,
            imageData: Data([0xFF, 0xD8, 0xFF])
        ),
        regionHash: regionHash
    )
}

private func stableHash() -> RegionHashDTO {
    regionHash(centerDistance: 0)
}

private func changedHash() -> RegionHashDTO {
    regionHash(centerDistance: 8)
}

private func regionHash(centerDistance: Int) -> RegionHashDTO {
    var distances = ScreenRegion.allCases.reduce(into: [ScreenRegion: Int]()) { result, region in
        result[region] = 0
    }
    distances[.center] = centerDistance
    return RegionHashDTO(
        globalDistance: 0,
        regionDistances: distances,
        changedRegions: centerDistance > 0 ? [.center] : []
    )
}
