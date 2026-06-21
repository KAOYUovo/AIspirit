import Foundation
import Perception

public actor PerceptionReplayRunner {
    public init() {}

    public func replay(
        _ scenario: ReplayScenario,
        config: PerceptionReplayConfig = PerceptionReplayConfig()
    ) async -> ReplayResult {
        let events = selectedEvents(from: scenario.events, config: config)
        let decisions = events.map(\.decision)
        let fallbackCount = decisions.filter(Self.isFallback).count
        let analyzedCount = decisions.filter { $0.kind == .analyze }.count
        let skippedCount = events.count - analyzedCount - fallbackCount

        return ReplayResult(
            scenarioID: scenario.id,
            totalEvents: events.count,
            analyzedCount: analyzedCount,
            skippedCount: max(0, skippedCount),
            fallbackCount: fallbackCount,
            decisions: decisions,
            petActions: events.map(\.petActions),
            effectiveFeatureFlags: events.map { config.overrideFeatureFlags ?? $0.featureFlags },
            mismatches: []
        )
    }

    private func selectedEvents(
        from events: [PerceptionDiagnosticEvent],
        config: PerceptionReplayConfig
    ) -> [PerceptionDiagnosticEvent] {
        guard !events.isEmpty else {
            return []
        }
        let start = min(max(config.startIndex ?? 0, 0), events.count)
        let endInclusive = min(max(config.endIndex ?? (events.count - 1), start - 1), events.count - 1)
        guard start <= endInclusive else {
            return []
        }
        return Array(events[start...endInclusive])
    }

    private static func isFallback(_ decision: GateDecision) -> Bool {
        decision.kind == .fallback || !decision.fallbacks.isEmpty
    }
}

