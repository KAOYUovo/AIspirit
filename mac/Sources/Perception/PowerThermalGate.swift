import Foundation

public struct PowerThermalGateResult: Equatable, Sendable {
    public var snapshot: PowerSnapshot
    public var mode: PerceptionMode
    public var decision: GateDecision?
    public var shouldUseLowPowerProfile: Bool

    public init(
        snapshot: PowerSnapshot,
        mode: PerceptionMode,
        decision: GateDecision?,
        shouldUseLowPowerProfile: Bool
    ) {
        self.snapshot = snapshot
        self.mode = mode
        self.decision = decision
        self.shouldUseLowPowerProfile = shouldUseLowPowerProfile
    }
}

public struct PowerThermalGate: Sendable {
    private let monitor: any PowerMonitoring
    private let parameters: PerceptionParameters

    public init(monitor: any PowerMonitoring, parameters: PerceptionParameters = .defaults) {
        self.monitor = monitor
        self.parameters = parameters
    }

    public func evaluate() async -> PowerThermalGateResult {
        do {
            return Self.evaluate(snapshot: try await monitor.currentPowerSnapshot(), parameters: parameters)
        } catch {
            return Self.evaluate(snapshot: .nominal, parameters: parameters)
        }
    }

    public static func evaluate(
        snapshot: PowerSnapshot,
        parameters: PerceptionParameters = .defaults
    ) -> PowerThermalGateResult {
        let reasons = reasonsForLowPower(snapshot: snapshot, parameters: parameters)

        guard reasons.isEmpty == false else {
            return PowerThermalGateResult(
                snapshot: snapshot,
                mode: .normal,
                decision: nil,
                shouldUseLowPowerProfile: false
            )
        }

        return PowerThermalGateResult(
            snapshot: snapshot,
            mode: .lowPower,
            decision: GateDecision(
                kind: .lowPowerThrottled,
                reasons: reasons,
                triggeredSignals: [],
                fallbacks: []
            ),
            shouldUseLowPowerProfile: true
        )
    }

    private static func reasonsForLowPower(
        snapshot: PowerSnapshot,
        parameters: PerceptionParameters
    ) -> [String] {
        var reasons: [String] = []

        if snapshot.thermalState >= parameters.thermalTrigger {
            reasons.append("thermal state \(snapshot.thermalState.rawValue)")
        }

        if let batteryLevel = snapshot.powerState.batteryLevel,
           batteryLevel < parameters.batteryLevelTrigger,
           snapshot.powerState.isCharging == false {
            reasons.append("battery below threshold")
        }

        if snapshot.powerState.isLowPowerMode {
            reasons.append("system low power mode")
        }

        return reasons
    }
}
