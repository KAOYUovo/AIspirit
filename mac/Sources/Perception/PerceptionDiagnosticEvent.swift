import Foundation

public struct PerceptionDiagnosticEvent: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var id: String
    public var timestamp: Date
    public var traceId: String
    public var spanId: String
    public var parentSpanId: String?
    public var module: String
    public var mode: PerceptionMode
    public var featureFlags: PerceptionFeatureFlags
    public var snapshot: ContextSnapshotHarnessDTO?
    public var coWatchingSnapshot: CoWatchingSnapshotHarnessDTO?
    public var decision: GateDecision
    public var latency: PerceptionLatency
    public var powerState: PowerState?
    public var thermalState: String?
    public var petActions: [PetActionDTO]
    public var errors: [DiagnosticErrorDTO]

    public init(
        schemaVersion: Int = 1,
        id: String,
        timestamp: Date,
        traceId: String,
        spanId: String,
        parentSpanId: String?,
        module: String = "perception",
        mode: PerceptionMode,
        featureFlags: PerceptionFeatureFlags,
        snapshot: ContextSnapshotHarnessDTO?,
        coWatchingSnapshot: CoWatchingSnapshotHarnessDTO?,
        decision: GateDecision,
        latency: PerceptionLatency,
        powerState: PowerState?,
        thermalState: String?,
        petActions: [PetActionDTO],
        errors: [DiagnosticErrorDTO]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.timestamp = timestamp
        self.traceId = traceId
        self.spanId = spanId
        self.parentSpanId = parentSpanId
        self.module = module
        self.mode = mode
        self.featureFlags = featureFlags
        self.snapshot = snapshot
        self.coWatchingSnapshot = coWatchingSnapshot
        self.decision = decision
        self.latency = latency
        self.powerState = powerState
        self.thermalState = thermalState
        self.petActions = petActions
        self.errors = errors
    }
}

public struct PerceptionLatency: Codable, Equatable, Sendable {
    public var idleMs: Int?
    public var frontAppMs: Int?
    public var captureMs: Int?
    public var streamMs: Int?
    public var hashMs: Int?
    public var keyframeMs: Int?
    public var ocrMs: Int?
    public var audioMs: Int?
    public var whisperMs: Int?
    public var contentTypeMs: Int?
    public var gateMs: Int?
    public var totalMs: Int?

    public init(
        idleMs: Int? = nil,
        frontAppMs: Int? = nil,
        captureMs: Int? = nil,
        streamMs: Int? = nil,
        hashMs: Int? = nil,
        keyframeMs: Int? = nil,
        ocrMs: Int? = nil,
        audioMs: Int? = nil,
        whisperMs: Int? = nil,
        contentTypeMs: Int? = nil,
        gateMs: Int? = nil,
        totalMs: Int? = nil
    ) {
        self.idleMs = idleMs
        self.frontAppMs = frontAppMs
        self.captureMs = captureMs
        self.streamMs = streamMs
        self.hashMs = hashMs
        self.keyframeMs = keyframeMs
        self.ocrMs = ocrMs
        self.audioMs = audioMs
        self.whisperMs = whisperMs
        self.contentTypeMs = contentTypeMs
        self.gateMs = gateMs
        self.totalMs = totalMs
    }
}

public struct PowerState: Codable, Equatable, Sendable {
    public var batteryLevel: Double?
    public var isCharging: Bool
    public var isLowPowerMode: Bool

    public init(batteryLevel: Double?, isCharging: Bool, isLowPowerMode: Bool) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
    }
}

public struct DiagnosticErrorDTO: Codable, Equatable, Sendable {
    public var module: String
    public var code: String
    public var message: String
    public var isFallbackApplied: Bool

    public init(module: String, code: String, message: String, isFallbackApplied: Bool) {
        self.module = module
        self.code = code
        self.message = message
        self.isFallbackApplied = isFallbackApplied
    }
}

