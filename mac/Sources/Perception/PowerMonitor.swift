import Foundation
import IOKit.ps

public struct PowerMonitor: PowerMonitoring {
    public init() {}

    public func currentPowerSnapshot() async throws -> PowerSnapshot {
        let processInfo = ProcessInfo.processInfo
        let batteryState = Self.currentBatteryState()

        return PowerSnapshot(
            powerState: PowerState(
                batteryLevel: batteryState.batteryLevel,
                isCharging: batteryState.isCharging,
                isLowPowerMode: processInfo.isLowPowerModeEnabled
            ),
            thermalState: ThermalTrigger(processInfoThermalState: processInfo.thermalState)
        )
    }

    private static func currentBatteryState() -> (batteryLevel: Double?, isCharging: Bool) {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return (nil, true)
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                let currentCapacity = numericValue(description[kIOPSCurrentCapacityKey as String]),
                let maxCapacity = numericValue(description[kIOPSMaxCapacityKey as String]),
                maxCapacity > 0
            else {
                continue
            }

            let isCharging = description[kIOPSIsChargingKey as String] as? Bool
                ?? ((description[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue)

            return (currentCapacity / maxCapacity, isCharging)
        }

        return (nil, true)
    }

    private static func numericValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        default:
            return nil
        }
    }
}

private extension ThermalTrigger {
    init(processInfoThermalState: ProcessInfo.ThermalState) {
        switch processInfoThermalState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .critical
        }
    }
}
