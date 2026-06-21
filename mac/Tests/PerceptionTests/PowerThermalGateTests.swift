import Foundation
import Testing
import Perception
import DebugTools

@Test func powerThermalGateUsesLowPowerForSeriousThermalState() async {
    let snapshot = PowerSnapshot(
        powerState: PowerState(batteryLevel: 0.9, isCharging: true, isLowPowerMode: false),
        thermalState: .serious
    )

    let result = await PowerThermalGate(monitor: MockPowerMonitor(snapshot: snapshot)).evaluate()

    #expect(result.shouldUseLowPowerProfile)
    #expect(result.mode == .lowPower)
    #expect(result.decision?.kind == .lowPowerThrottled)
    #expect(result.decision?.reasons == ["thermal state serious"])
}

@Test func powerThermalGateUsesLowPowerForLowBatteryWhenUnplugged() {
    let snapshot = PowerSnapshot(
        powerState: PowerState(batteryLevel: 0.19, isCharging: false, isLowPowerMode: false),
        thermalState: .nominal
    )

    let result = PowerThermalGate.evaluate(snapshot: snapshot)

    #expect(result.shouldUseLowPowerProfile)
    #expect(result.mode == .lowPower)
    #expect(result.decision?.kind == .lowPowerThrottled)
    #expect(result.decision?.reasons == ["battery below threshold"])
}

@Test func powerThermalGateDoesNotUseLowPowerForChargingOrThresholdBattery() {
    let charging = PowerSnapshot(
        powerState: PowerState(batteryLevel: 0.1, isCharging: true, isLowPowerMode: false),
        thermalState: .nominal
    )
    let atThreshold = PowerSnapshot(
        powerState: PowerState(batteryLevel: 0.2, isCharging: false, isLowPowerMode: false),
        thermalState: .nominal
    )

    #expect(PowerThermalGate.evaluate(snapshot: charging).shouldUseLowPowerProfile == false)
    #expect(PowerThermalGate.evaluate(snapshot: atThreshold).shouldUseLowPowerProfile == false)
}

@Test func powerThermalGateUsesLowPowerForSystemLowPowerMode() {
    let snapshot = PowerSnapshot(
        powerState: PowerState(batteryLevel: nil, isCharging: true, isLowPowerMode: true),
        thermalState: .nominal
    )

    let result = PowerThermalGate.evaluate(snapshot: snapshot)

    #expect(result.shouldUseLowPowerProfile)
    #expect(result.decision?.reasons == ["system low power mode"])
}

@Test func powerThermalGateUsesInjectedThresholds() {
    let snapshot = PowerSnapshot(
        powerState: PowerState(batteryLevel: 0.29, isCharging: false, isLowPowerMode: false),
        thermalState: .fair
    )
    let parameters = PerceptionParameters(thermalTrigger: .critical, batteryLevelTrigger: 0.3)

    let result = PowerThermalGate.evaluate(snapshot: snapshot, parameters: parameters)

    #expect(result.shouldUseLowPowerProfile)
    #expect(result.decision?.reasons == ["battery below threshold"])
}

@Test func powerThermalGateFallsBackToNormalWhenMonitorFails() async {
    let gate = PowerThermalGate(monitor: MockPowerMonitor(error: .unavailable("power")))

    let result = await gate.evaluate()

    #expect(result.snapshot == .nominal)
    #expect(result.shouldUseLowPowerProfile == false)
    #expect(result.decision == nil)
}
