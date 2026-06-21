import Foundation
import Perception

public enum MockScenarioKind: String, Codable, CaseIterable, Sendable {
    case busyTyping
    case switchToChat
    case staticReading
    case coWatchingSports
    case screenLocked
    case streamFallback
}

public struct MockScenarioFactory: Sendable {
    public init() {}

    public func make(_ kind: MockScenarioKind) -> ReplayScenario {
        switch kind {
        case .busyTyping:
            return scenario(
                id: "busy-typing",
                name: "Busy Typing",
                description: "VS Code foreground, repeated recent input, small region changes.",
                events: [
                    normalEvent(id: "busy-1", appName: "Visual Studio Code", attentionState: .busy, idleDuration: 1.2, recentInputActive: true, globalDistance: 2, regionDistance: 4, decision: .analyze),
                    normalEvent(id: "busy-2", appName: "Visual Studio Code", attentionState: .busy, idleDuration: 3.4, recentInputActive: true, globalDistance: 1, regionDistance: 3, decision: .skipStable),
                    normalEvent(id: "busy-3", appName: "Visual Studio Code", attentionState: .busy, idleDuration: 2.0, recentInputActive: true, globalDistance: 3, regionDistance: 5, decision: .analyze)
                ]
            )
        case .switchToChat:
            return scenario(
                id: "switch-to-chat",
                name: "Switch To Chat",
                description: "Foreground app switches from VS Code to WeChat.",
                events: [
                    normalEvent(id: "chat-1", appName: "Visual Studio Code", windowTitles: ["Perception.swift"], attentionState: .busy, decision: .skipStable),
                    normalEvent(id: "chat-2", appName: "WeChat", windowTitles: ["Chat"], attentionState: .observing, decision: .analyze, signals: [.appChanged, .windowTitleChanged])
                ]
            )
        case .staticReading:
            return scenario(
                id: "static-reading",
                name: "Static Reading",
                description: "Safari foreground with no input and stable screen.",
                events: [
                    normalEvent(id: "reading-1", appName: "Safari", windowTitles: ["Article"], attentionState: .observing, idleDuration: 12, recentInputActive: false, decision: .skipStable),
                    normalEvent(id: "reading-2", appName: "Safari", windowTitles: ["Article"], attentionState: .observing, idleDuration: 28, recentInputActive: false, decision: .skipStable),
                    normalEvent(id: "reading-3", appName: "Safari", windowTitles: ["Article"], attentionState: .observing, idleDuration: 45, recentInputActive: false, decision: .analyze, signals: [.forceRefreshInterval])
                ]
            )
        case .coWatchingSports:
            return scenario(
                id: "co-watching-sports",
                name: "Co-watching Sports",
                description: "Dynamic sports content with OCR score and transcript.",
                events: [
                    coWatchingEvent(id: "sports-1", transcript: "final minute, two point game"),
                    coWatchingEvent(id: "sports-2", transcript: "three pointer from the corner")
                ]
            )
        case .screenLocked:
            return scenario(
                id: "screen-locked",
                name: "Screen Locked",
                description: "Screen locked state pauses perception and records no snapshot.",
                events: [
                    event(
                        id: "locked-1",
                        mode: .paused,
                        snapshot: nil,
                        coWatchingSnapshot: nil,
                        decision: GateDecision(
                            kind: .pausedScreenLocked,
                            reasons: ["screen locked"],
                            triggeredSignals: [],
                            fallbacks: []
                        ),
                        latency: PerceptionLatency(gateMs: 0, totalMs: 0),
                        petActions: []
                    )
                ]
            )
        case .streamFallback:
            var flags = PerceptionFeatureFlags()
            flags.coWatchingStream = true
            flags.keyframeExtraction = true
            return scenario(
                id: "stream-fallback",
                name: "Stream Fallback",
                description: "Screen stream enabled but start fails, falling back to multi-frame screenshots.",
                events: [
                    event(
                        id: "stream-fallback-1",
                        mode: .coWatching,
                        featureFlags: flags,
                        snapshot: nil,
                        coWatchingSnapshot: nil,
                        decision: GateDecision(
                            kind: .fallback,
                            reasons: ["stream start failed"],
                            triggeredSignals: [.dynamicContent],
                            fallbacks: ["multiFrameSingleCapture"]
                        ),
                        latency: PerceptionLatency(streamMs: 5, totalMs: 5),
                        errors: [
                            DiagnosticErrorDTO(
                                module: "perception",
                                code: "streamStartFailed",
                                message: "mock stream start error",
                                isFallbackApplied: true
                            )
                        ],
                        petActions: []
                    )
                ]
            )
        }
    }

    private func scenario(id: String, name: String, description: String, events: [PerceptionDiagnosticEvent]) -> ReplayScenario {
        ReplayScenario(id: id, name: name, description: description, events: events)
    }

    private func normalEvent(
        id: String,
        appName: String,
        windowTitles: [String] = ["main"],
        attentionState: AttentionState,
        idleDuration: TimeInterval = 2,
        recentInputActive: Bool = true,
        globalDistance: Int = 0,
        regionDistance: Int = 0,
        decision: GateDecisionKind,
        signals: [TriggerSignal] = [.recentInputActive]
    ) -> PerceptionDiagnosticEvent {
        let timestamp = timestamp(offset: id)
        return event(
            id: id,
            mode: .normal,
            snapshot: ContextSnapshotHarnessDTO(
                id: "snapshot-\(id)",
                timestamp: timestamp,
                appName: appName,
                windowTitles: windowTitles,
                idleDuration: idleDuration,
                recentInputActive: recentInputActive,
                attentionState: attentionState,
                regionHash: RegionHashDTO(
                    globalDistance: globalDistance,
                    regionDistances: [.bottomRight: regionDistance],
                    changedRegions: regionDistance > 0 ? [.bottomRight] : []
                ),
                screenshotRef: nil,
                isDynamicContent: false,
                contentType: appName == "Visual Studio Code" ? .coding : .unknown
            ),
            coWatchingSnapshot: nil,
            decision: GateDecision(
                kind: decision,
                reasons: [decision.rawValue],
                triggeredSignals: signals,
                fallbacks: []
            ),
            latency: PerceptionLatency(gateMs: 1, totalMs: 2),
            petActions: attentionState == .busy ? [PetActionDTO(type: .suppressBubble, payload: ["reason": "attentionState=busy"])] : []
        )
    }

    private func coWatchingEvent(id: String, transcript: String) -> PerceptionDiagnosticEvent {
        let timestamp = timestamp(offset: id)
        return event(
            id: id,
            mode: .coWatching,
            snapshot: nil,
            coWatchingSnapshot: CoWatchingSnapshotHarnessDTO(
                id: "cowatch-\(id)",
                timestampStart: timestamp,
                timestampEnd: timestamp.addingTimeInterval(5),
                appName: "Safari",
                windowTitles: ["NBA Finals Live"],
                keyframeRefs: ["keyframes/\(id)-1.jpg", "keyframes/\(id)-2.jpg"],
                ocrText: ["LAL 98 BOS 96"],
                audioTranscript: transcript,
                contentType: .sports,
                recentSummary: "close basketball game"
            ),
            decision: GateDecision(
                kind: .analyze,
                reasons: ["dynamic sports content"],
                triggeredSignals: [.dynamicContent, .coWatchingKeyframe],
                fallbacks: []
            ),
            latency: PerceptionLatency(keyframeMs: 2, ocrMs: 8, whisperMs: 10, contentTypeMs: 1, totalMs: 21),
            petActions: [PetActionDTO(type: .enterCoWatching, payload: ["contentType": "sports"])]
        )
    }

    private func event(
        id: String,
        mode: PerceptionMode,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        snapshot: ContextSnapshotHarnessDTO?,
        coWatchingSnapshot: CoWatchingSnapshotHarnessDTO?,
        decision: GateDecision,
        latency: PerceptionLatency,
        errors: [DiagnosticErrorDTO] = [],
        petActions: [PetActionDTO]
    ) -> PerceptionDiagnosticEvent {
        PerceptionDiagnosticEvent(
            id: id,
            timestamp: timestamp(offset: id),
            traceId: "trace-\(id)",
            spanId: "span-perception-\(id)",
            parentSpanId: nil,
            mode: mode,
            featureFlags: featureFlags,
            snapshot: snapshot,
            coWatchingSnapshot: coWatchingSnapshot,
            decision: decision,
            latency: latency,
            powerState: nil,
            thermalState: nil,
            petActions: petActions,
            errors: errors
        )
    }

    private func timestamp(offset: String) -> Date {
        let stableOffset = abs(offset.utf8.reduce(0) { ($0 * 31 + Int($1)) % 3_600 })
        return Date(timeIntervalSince1970: 1_780_000_000 + TimeInterval(stableOffset))
    }
}
