import Foundation

public struct VLMAnalysisRequest: Equatable, Sendable {
    public var traceId: String
    public var timestamp: Date
    public var mode: PerceptionMode
    public var snapshot: ContextSnapshotHarnessDTO?

    public init(
        traceId: String,
        timestamp: Date,
        mode: PerceptionMode,
        snapshot: ContextSnapshotHarnessDTO?
    ) {
        self.traceId = traceId
        self.timestamp = timestamp
        self.mode = mode
        self.snapshot = snapshot
    }
}

public struct VLMAnalysisResult: Equatable, Sendable {
    public var summary: String?
    public var contentType: ContentType?

    public init(summary: String? = nil, contentType: ContentType? = nil) {
        self.summary = summary
        self.contentType = contentType
    }
}

public protocol VLMAnalyzing: Sendable {
    func analyze(_ request: VLMAnalysisRequest) async throws -> VLMAnalysisResult
}

public struct DisabledVLMAnalyzer: VLMAnalyzing {
    public init() {}

    public func analyze(_ request: VLMAnalysisRequest) async throws -> VLMAnalysisResult {
        VLMAnalysisResult()
    }
}

public enum PerceptionSchedulerOutcome: String, Codable, Equatable, Sendable {
    case analyzed
    case skipped
    case fallback
}

public struct PerceptionSchedulerTickResult: Equatable, Sendable {
    public var outcome: PerceptionSchedulerOutcome
    public var didInvokeVLM: Bool
    public var analysis: VLMAnalysisResult?
    public var diagnosticEvent: PerceptionDiagnosticEvent

    public init(
        outcome: PerceptionSchedulerOutcome,
        didInvokeVLM: Bool,
        analysis: VLMAnalysisResult?,
        diagnosticEvent: PerceptionDiagnosticEvent
    ) {
        self.outcome = outcome
        self.didInvokeVLM = didInvokeVLM
        self.analysis = analysis
        self.diagnosticEvent = diagnosticEvent
    }
}

public enum PerceptionSchedulerError: Error, Equatable, Sendable {
    case vlmTimeout
}

public actor PerceptionScheduler {
    private let gateChain: GateChain
    private let analyzer: any VLMAnalyzing
    private let parameters: PerceptionParameters
    private let diagnostics: PerceptionDiagnostics?
    private let logger: (any Logging)?
    private var isAIAnalyzing = false
    private var latestPendingInput: GateChainInput?
    private var vlmCallTimestamps: [Date] = []

    public init(
        gateChain: GateChain? = nil,
        analyzer: any VLMAnalyzing = DisabledVLMAnalyzer(),
        parameters: PerceptionParameters = .defaults,
        diagnostics: PerceptionDiagnostics? = nil,
        logger: (any Logging)? = nil
    ) {
        self.gateChain = gateChain ?? GateChain(parameters: parameters)
        self.analyzer = analyzer
        self.parameters = parameters
        self.diagnostics = diagnostics
        self.logger = logger
    }

    public func runTick(_ input: GateChainInput) async -> PerceptionSchedulerTickResult {
        var effectiveInput = input
        effectiveInput.aiBusy = isAIAnalyzing

        let gateResult = gateChain.evaluate(effectiveInput)
        if isAIAnalyzing {
            latestPendingInput = input
            return await finish(
                outcome: .skipped,
                didInvokeVLM: false,
                analysis: nil,
                event: gateResult.diagnosticEvent
            )
        }

        guard gateResult.shouldAnalyze else {
            return await finish(
                outcome: .skipped,
                didInvokeVLM: false,
                analysis: nil,
                event: gateResult.diagnosticEvent
            )
        }

        guard canSpendVLMBudget(at: input.timestamp) else {
            let event = eventByReplacingDecision(
                gateResult.diagnosticEvent,
                decision: GateDecision(
                    kind: .skipStable,
                    reasons: ["VLM hourly budget exhausted"],
                    triggeredSignals: [],
                    fallbacks: []
                )
            )
            return await finish(
                outcome: .skipped,
                didInvokeVLM: false,
                analysis: nil,
                event: event
            )
        }

        spendVLMBudget(at: input.timestamp)
        isAIAnalyzing = true
        defer {
            isAIAnalyzing = false
        }

        let request = VLMAnalysisRequest(
            traceId: input.traceId,
            timestamp: input.timestamp,
            mode: gateResult.mode,
            snapshot: gateResult.diagnosticEvent.snapshot
        )

        do {
            let analysis = try await analyzeWithTimeout(request)
            return await finish(
                outcome: .analyzed,
                didInvokeVLM: true,
                analysis: analysis,
                event: gateResult.diagnosticEvent
            )
        } catch PerceptionSchedulerError.vlmTimeout {
            return await finish(
                outcome: .fallback,
                didInvokeVLM: true,
                analysis: nil,
                event: fallbackEvent(
                    from: gateResult.diagnosticEvent,
                    code: "vlmTimeout",
                    message: "VLM analysis exceeded configured timeout"
                )
            )
        } catch {
            return await finish(
                outcome: .fallback,
                didInvokeVLM: true,
                analysis: nil,
                event: fallbackEvent(
                    from: gateResult.diagnosticEvent,
                    code: "vlmFailed",
                    message: String(describing: error)
                )
            )
        }
    }

    public func pendingTick() -> GateChainInput? {
        latestPendingInput
    }

    public func drainLatestTick() async -> PerceptionSchedulerTickResult? {
        guard let pending = latestPendingInput else {
            return nil
        }
        latestPendingInput = nil
        return await runTick(pending)
    }

    private func canSpendVLMBudget(at timestamp: Date) -> Bool {
        pruneVLMBudget(now: timestamp)
        return vlmCallTimestamps.count < parameters.vlmMaxPerHour
    }

    private func spendVLMBudget(at timestamp: Date) {
        pruneVLMBudget(now: timestamp)
        vlmCallTimestamps.append(timestamp)
    }

    private func pruneVLMBudget(now: Date) {
        let cutoff = now.addingTimeInterval(-60 * 60)
        vlmCallTimestamps.removeAll { $0 < cutoff }
    }

    private func analyzeWithTimeout(_ request: VLMAnalysisRequest) async throws -> VLMAnalysisResult {
        let analyzer = analyzer
        let timeout = Self.nanoseconds(from: parameters.vlmTimeout)

        return try await withCheckedThrowingContinuation { continuation in
            let race = SchedulerTimeoutRace<VLMAnalysisResult>()
            let analyzerTask = Task {
                try await analyzer.analyze(request)
            }

            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: timeout)
                analyzerTask.cancel()
                race.resume(.failure(PerceptionSchedulerError.vlmTimeout), continuation: continuation)
            }

            Task {
                do {
                    let result = try await analyzerTask.value
                    timeoutTask.cancel()
                    race.resume(.success(result), continuation: continuation)
                } catch {
                    timeoutTask.cancel()
                    race.resume(.failure(error), continuation: continuation)
                }
            }
        }
    }

    private func finish(
        outcome: PerceptionSchedulerOutcome,
        didInvokeVLM: Bool,
        analysis: VLMAnalysisResult?,
        event: PerceptionDiagnosticEvent
    ) async -> PerceptionSchedulerTickResult {
        await diagnostics?.record(event)
        logger?.log(
            outcome == .fallback ? .warning : .debug,
            "perception scheduler tick",
            module: "perception",
            traceId: event.traceId,
            metadata: [
                "outcome": outcome.rawValue,
                "decision": event.decision.kind.rawValue,
                "didInvokeVLM": String(didInvokeVLM)
            ]
        )
        return PerceptionSchedulerTickResult(
            outcome: outcome,
            didInvokeVLM: didInvokeVLM,
            analysis: analysis,
            diagnosticEvent: event
        )
    }

    private func fallbackEvent(
        from event: PerceptionDiagnosticEvent,
        code: String,
        message: String
    ) -> PerceptionDiagnosticEvent {
        var updated = eventByReplacingDecision(
            event,
            decision: GateDecision(
                kind: .fallback,
                reasons: ["VLM analysis unavailable"],
                triggeredSignals: event.decision.triggeredSignals,
                fallbacks: ["skip VLM result for this tick"]
            )
        )
        updated.errors.append(
            DiagnosticErrorDTO(
                module: "perception",
                code: code,
                message: message,
                isFallbackApplied: true
            )
        )
        return updated
    }

    private func eventByReplacingDecision(
        _ event: PerceptionDiagnosticEvent,
        decision: GateDecision
    ) -> PerceptionDiagnosticEvent {
        var updated = event
        updated.decision = decision
        return updated
    }

    private static func nanoseconds(from seconds: TimeInterval) -> UInt64 {
        UInt64(max(0, seconds) * 1_000_000_000)
    }
}

private final class SchedulerTimeoutRace<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(
        _ result: Result<Value, Error>,
        continuation: CheckedContinuation<Value, Error>
    ) {
        let shouldResume = lock.withLock {
            if didResume {
                return false
            }
            didResume = true
            return true
        }

        guard shouldResume else {
            return
        }

        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
