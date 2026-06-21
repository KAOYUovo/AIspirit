import Foundation

public enum CaptureStrategy: String, Codable, Equatable, Sendable {
    case none
    case singleFrame
    case stream
}

public struct GateChainInput: Equatable, Sendable {
    public var timestamp: Date
    public var traceId: String
    public var parentSpanId: String?
    public var featureFlags: PerceptionFeatureFlags
    public var screenState: ScreenState
    public var powerSnapshot: PowerSnapshot
    public var idleDuration: TimeInterval
    public var frontAppSnapshot: FrontAppSnapshot
    public var previousFrontAppSnapshot: FrontAppSnapshot?
    public var regionHash: RegionHashDTO?
    public var recentInputActive: Bool
    public var aiBusy: Bool
    public var secondsSinceLastAnalysis: TimeInterval
    public var secondsSinceLastAI: TimeInterval
    public var attentionState: AttentionState
    public var isDynamicContent: Bool

    public init(
        timestamp: Date = Date(),
        traceId: String = UUID().uuidString,
        parentSpanId: String? = nil,
        featureFlags: PerceptionFeatureFlags = PerceptionFeatureFlags(),
        screenState: ScreenState = .active,
        powerSnapshot: PowerSnapshot = .nominal,
        idleDuration: TimeInterval = 0,
        frontAppSnapshot: FrontAppSnapshot = .unknown,
        previousFrontAppSnapshot: FrontAppSnapshot? = nil,
        regionHash: RegionHashDTO? = nil,
        recentInputActive: Bool = false,
        aiBusy: Bool = false,
        secondsSinceLastAnalysis: TimeInterval = 0,
        secondsSinceLastAI: TimeInterval = 0,
        attentionState: AttentionState = .observing,
        isDynamicContent: Bool = false
    ) {
        self.timestamp = timestamp
        self.traceId = traceId
        self.parentSpanId = parentSpanId
        self.featureFlags = featureFlags
        self.screenState = screenState
        self.powerSnapshot = powerSnapshot
        self.idleDuration = idleDuration
        self.frontAppSnapshot = frontAppSnapshot
        self.previousFrontAppSnapshot = previousFrontAppSnapshot
        self.regionHash = regionHash
        self.recentInputActive = recentInputActive
        self.aiBusy = aiBusy
        self.secondsSinceLastAnalysis = secondsSinceLastAnalysis
        self.secondsSinceLastAI = secondsSinceLastAI
        self.attentionState = attentionState
        self.isDynamicContent = isDynamicContent
    }
}

public struct GateChainResult: Equatable, Sendable {
    public var decision: GateDecision
    public var mode: PerceptionMode
    public var captureStrategy: CaptureStrategy
    public var shouldAnalyze: Bool
    public var diagnosticEvent: PerceptionDiagnosticEvent

    public init(
        decision: GateDecision,
        mode: PerceptionMode,
        captureStrategy: CaptureStrategy,
        shouldAnalyze: Bool,
        diagnosticEvent: PerceptionDiagnosticEvent
    ) {
        self.decision = decision
        self.mode = mode
        self.captureStrategy = captureStrategy
        self.shouldAnalyze = shouldAnalyze
        self.diagnosticEvent = diagnosticEvent
    }
}

public struct GateChain: Sendable {
    private let parameters: PerceptionParameters
    private let privacyBlocklist: PrivacyBlocklist

    public init(parameters: PerceptionParameters = .defaults, privacyBlocklist: PrivacyBlocklist = .defaults) {
        self.parameters = parameters
        self.privacyBlocklist = privacyBlocklist
    }

    public func evaluate(_ input: GateChainInput) -> GateChainResult {
        let start = Date()
        let frontAppGate = FrontAppGate.evaluate(
            snapshot: input.frontAppSnapshot,
            previousSnapshot: input.previousFrontAppSnapshot,
            blocklist: privacyBlocklist
        )

        if let decision = ScreenStateGate.evaluate(screenState: input.screenState).decision {
            return result(decision: decision, mode: .paused, captureStrategy: .none, input: input, start: start)
        }

        if let decision = PowerThermalGate.evaluate(snapshot: input.powerSnapshot, parameters: parameters).decision {
            return result(decision: decision, mode: .lowPower, captureStrategy: .none, input: input, start: start)
        }

        if let decision = IdleGate.evaluate(idleDuration: input.idleDuration, parameters: parameters).decision {
            return result(decision: decision, mode: .normal, captureStrategy: .none, input: input, start: start)
        }

        if let decision = frontAppGate.decision, decision.kind == .skipPrivacyBlocked {
            return result(decision: decision, mode: .normal, captureStrategy: .none, input: input, start: start)
        }

        if input.aiBusy {
            return result(
                decision: GateDecision(
                    kind: .skipAIBusy,
                    reasons: ["previous AI analysis still running"],
                    triggeredSignals: [],
                    fallbacks: []
                ),
                mode: .normal,
                captureStrategy: .none,
                input: input,
                start: start
            )
        }

        let signals = analysisSignals(input: input, frontAppGate: frontAppGate)
        if signals.isEmpty == false {
            return result(
                decision: GateDecision(
                    kind: .analyze,
                    reasons: reasons(for: signals),
                    triggeredSignals: signals,
                    fallbacks: []
                ),
                mode: .normal,
                captureStrategy: .singleFrame,
                input: input,
                start: start
            )
        }

        return result(
            decision: GateDecision(
                kind: .skipStable,
                reasons: ["no trigger signal before force refresh interval"],
                triggeredSignals: [],
                fallbacks: []
            ),
            mode: .normal,
            captureStrategy: .none,
            input: input,
            start: start
        )
    }

    private func analysisSignals(input: GateChainInput, frontAppGate: FrontAppGateResult) -> [TriggerSignal] {
        var signals: [TriggerSignal] = []

        if let frontAppDecision = frontAppGate.decision, frontAppDecision.kind == .analyze {
            signals.append(contentsOf: frontAppDecision.triggeredSignals)
        }

        if let regionHash = input.regionHash, regionHash.hasSignificantChange(parameters: parameters) {
            signals.append(.regionHashChanged)
        }

        if input.recentInputActive && input.secondsSinceLastAI >= parameters.normalMinAIInterval {
            signals.append(.recentInputActive)
        }

        if input.isDynamicContent {
            signals.append(.dynamicContent)
        }

        if input.secondsSinceLastAnalysis >= parameters.forceRefreshInterval {
            signals.append(.forceRefreshInterval)
        }

        return unique(signals)
    }

    private func result(
        decision: GateDecision,
        mode: PerceptionMode,
        captureStrategy: CaptureStrategy,
        input: GateChainInput,
        start: Date
    ) -> GateChainResult {
        let diagnosticEvent = diagnosticEvent(
            decision: decision,
            mode: mode,
            input: input,
            latencyMs: max(0, Int(Date().timeIntervalSince(start) * 1000))
        )
        return GateChainResult(
            decision: decision,
            mode: mode,
            captureStrategy: captureStrategy,
            shouldAnalyze: decision.kind == .analyze,
            diagnosticEvent: diagnosticEvent
        )
    }

    private func diagnosticEvent(
        decision: GateDecision,
        mode: PerceptionMode,
        input: GateChainInput,
        latencyMs: Int
    ) -> PerceptionDiagnosticEvent {
        PerceptionDiagnosticEvent(
            id: UUID().uuidString,
            timestamp: input.timestamp,
            traceId: input.traceId,
            spanId: UUID().uuidString,
            parentSpanId: input.parentSpanId,
            mode: mode,
            featureFlags: input.featureFlags,
            snapshot: ContextSnapshotHarnessDTO(
                id: UUID().uuidString,
                timestamp: input.timestamp,
                appName: input.frontAppSnapshot.appName,
                windowTitles: input.frontAppSnapshot.windowTitles,
                idleDuration: input.idleDuration,
                recentInputActive: input.recentInputActive,
                attentionState: input.attentionState,
                regionHash: input.regionHash,
                screenshotRef: nil,
                isDynamicContent: input.isDynamicContent,
                contentType: nil
            ),
            coWatchingSnapshot: nil,
            decision: decision,
            latency: PerceptionLatency(gateMs: latencyMs, totalMs: latencyMs),
            powerState: input.powerSnapshot.powerState,
            thermalState: input.powerSnapshot.thermalState.rawValue,
            petActions: [],
            errors: []
        )
    }

    private func reasons(for signals: [TriggerSignal]) -> [String] {
        signals.map { signal in
            switch signal {
            case .regionHashChanged:
                return "region hash changed"
            case .appChanged:
                return "front app changed"
            case .windowTitleChanged:
                return "window title changed"
            case .recentInputActive:
                return "recent input active and minimum AI interval reached"
            case .forceRefreshInterval:
                return "force refresh interval reached"
            case .dynamicContent:
                return "dynamic content detected"
            case .userInvoked:
                return "user invoked perception"
            case .coWatchingKeyframe:
                return "co-watching keyframe selected"
            }
        }
    }

    private func unique(_ signals: [TriggerSignal]) -> [TriggerSignal] {
        var seen = Set<TriggerSignal>()
        return signals.filter { seen.insert($0).inserted }
    }
}
