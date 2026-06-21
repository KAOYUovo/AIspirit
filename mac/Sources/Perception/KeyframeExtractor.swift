import Foundation

public struct KeyframeExtractorConfig: Codable, Equatable, Sendable {
    public var sampleInterval: TimeInterval
    public var retentionWindow: TimeInterval
    public var maxKeyframes: Int

    public init(
        sampleInterval: TimeInterval = 1,
        retentionWindow: TimeInterval = 10,
        maxKeyframes: Int = 5
    ) {
        self.sampleInterval = sampleInterval
        self.retentionWindow = retentionWindow
        self.maxKeyframes = maxKeyframes
    }
}

public struct KeyframeCandidate: Equatable, Sendable {
    public var frame: CapturedFrame
    public var regionHash: RegionHashDTO?

    public init(frame: CapturedFrame, regionHash: RegionHashDTO? = nil) {
        self.frame = frame
        self.regionHash = regionHash
    }
}

public struct KeyframeExtractionResult: Equatable, Sendable {
    public var didRun: Bool
    public var keyframes: [CapturedFrame]
    public var decision: GateDecision
    public var diagnosticEvent: PerceptionDiagnosticEvent?

    public init(
        didRun: Bool,
        keyframes: [CapturedFrame],
        decision: GateDecision,
        diagnosticEvent: PerceptionDiagnosticEvent?
    ) {
        self.didRun = didRun
        self.keyframes = keyframes
        self.decision = decision
        self.diagnosticEvent = diagnosticEvent
    }
}

public struct KeyframeExtractor: Sendable {
    private let featureFlags: PerceptionFeatureFlags
    private let parameters: PerceptionParameters
    private let config: KeyframeExtractorConfig

    public init(
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        parameters: PerceptionParameters = .defaults,
        config: KeyframeExtractorConfig = KeyframeExtractorConfig()
    ) {
        self.featureFlags = featureFlags
        self.parameters = parameters
        self.config = config
    }

    public func extract(
        from candidates: [KeyframeCandidate],
        traceId: String = UUID().uuidString,
        parentSpanId: String? = nil
    ) -> KeyframeExtractionResult {
        guard featureFlags.keyframeExtraction else {
            return KeyframeExtractionResult(
                didRun: false,
                keyframes: [],
                decision: GateDecision(
                    kind: .skipStable,
                    reasons: ["keyframe extraction disabled by feature flag"],
                    triggeredSignals: [],
                    fallbacks: []
                ),
                diagnosticEvent: nil
            )
        }

        let start = Date()
        let sampled = fixedIntervalSample(candidates.sorted { $0.frame.timestamp < $1.frame.timestamp })
        let selected = selectChangedFrames(sampled)
        let retained = retainRecent(selected)
        let reasons = retainedReasons(hasHashInput: sampled.contains { $0.regionHash != nil }, selectedCount: retained.count)
        let decision = GateDecision(
            kind: retained.isEmpty ? .skipStable : .analyze,
            reasons: reasons,
            triggeredSignals: retained.isEmpty ? [] : [.coWatchingKeyframe],
            fallbacks: sampled.contains { $0.regionHash == nil } ? ["fixed interval sampling"] : []
        )

        return KeyframeExtractionResult(
            didRun: true,
            keyframes: retained.map(\.frame),
            decision: decision,
            diagnosticEvent: diagnosticEvent(
                candidates: candidates,
                keyframes: retained,
                decision: decision,
                traceId: traceId,
                parentSpanId: parentSpanId,
                latencyMs: max(0, Int(Date().timeIntervalSince(start) * 1000))
            )
        )
    }

    private func fixedIntervalSample(_ candidates: [KeyframeCandidate]) -> [KeyframeCandidate] {
        guard config.sampleInterval > 0 else {
            return candidates
        }

        var sampled: [KeyframeCandidate] = []
        var lastSampleTimestamp: Date?

        for candidate in candidates {
            guard let lastTimestamp = lastSampleTimestamp else {
                sampled.append(candidate)
                lastSampleTimestamp = candidate.frame.timestamp
                continue
            }

            if candidate.frame.timestamp.timeIntervalSince(lastTimestamp) >= config.sampleInterval {
                sampled.append(candidate)
                lastSampleTimestamp = candidate.frame.timestamp
            }
        }

        return sampled
    }

    private func selectChangedFrames(_ sampled: [KeyframeCandidate]) -> [KeyframeCandidate] {
        var selected: [KeyframeCandidate] = []

        for candidate in sampled {
            guard selected.isEmpty == false else {
                selected.append(candidate)
                continue
            }

            guard let regionHash = candidate.regionHash else {
                selected.append(candidate)
                continue
            }

            if regionHash.hasSignificantChange(parameters: parameters) {
                selected.append(candidate)
            }
        }

        return selected
    }

    private func retainRecent(_ selected: [KeyframeCandidate]) -> [KeyframeCandidate] {
        guard let latestTimestamp = selected.last?.frame.timestamp else {
            return []
        }

        let cutoff = latestTimestamp.addingTimeInterval(-max(0, config.retentionWindow))
        let recent = selected.filter { $0.frame.timestamp >= cutoff }
        guard config.maxKeyframes > 0 else {
            return []
        }
        return Array(recent.suffix(config.maxKeyframes))
    }

    private func retainedReasons(hasHashInput: Bool, selectedCount: Int) -> [String] {
        guard selectedCount > 0 else {
            return ["no keyframe selected"]
        }

        if hasHashInput {
            return ["fixed interval sample selected", "region hash change selected keyframe"]
        }
        return ["fixed interval sample selected"]
    }

    private func diagnosticEvent(
        candidates: [KeyframeCandidate],
        keyframes: [KeyframeCandidate],
        decision: GateDecision,
        traceId: String,
        parentSpanId: String?,
        latencyMs: Int
    ) -> PerceptionDiagnosticEvent {
        let timestamp = keyframes.last?.frame.timestamp ?? candidates.last?.frame.timestamp ?? Date()
        return PerceptionDiagnosticEvent(
            id: UUID().uuidString,
            timestamp: timestamp,
            traceId: traceId,
            spanId: UUID().uuidString,
            parentSpanId: parentSpanId,
            mode: .coWatching,
            featureFlags: featureFlags,
            snapshot: nil,
            coWatchingSnapshot: CoWatchingSnapshotHarnessDTO(
                id: UUID().uuidString,
                timestampStart: candidates.first?.frame.timestamp ?? timestamp,
                timestampEnd: timestamp,
                appName: "unknown",
                windowTitles: [],
                keyframeRefs: keyframes.map(\.frame.id),
                ocrText: [],
                audioTranscript: nil,
                contentType: .unknown,
                recentSummary: nil
            ),
            decision: decision,
            latency: PerceptionLatency(keyframeMs: latencyMs, totalMs: latencyMs),
            powerState: nil,
            thermalState: nil,
            petActions: [],
            errors: []
        )
    }

}
