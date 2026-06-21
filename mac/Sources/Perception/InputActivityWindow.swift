import Foundation

public struct InputActivityWindow: Sendable {
    public private(set) var recentActiveTimestamps: [Date]
    private let parameters: PerceptionParameters

    public init(
        parameters: PerceptionParameters = .defaults,
        recentActiveTimestamps: [Date] = []
    ) {
        self.parameters = parameters
        self.recentActiveTimestamps = recentActiveTimestamps.sorted()
    }

    public mutating func record(timestamp: Date, idleDuration: TimeInterval) -> InputActivityState {
        if idleDuration < parameters.instantInputThreshold {
            recentActiveTimestamps.append(timestamp)
        }
        prune(relativeTo: timestamp)
        return state(at: timestamp)
    }

    public mutating func prune(relativeTo timestamp: Date) {
        recentActiveTimestamps.removeAll { activeTimestamp in
            timestamp.timeIntervalSince(activeTimestamp) > parameters.inputActiveWindow
                || activeTimestamp > timestamp
        }
    }

    public func state(at timestamp: Date) -> InputActivityState {
        let recentTimestamps = recentActiveTimestamps.filter { activeTimestamp in
            let age = timestamp.timeIntervalSince(activeTimestamp)
            return age >= 0 && age <= parameters.inputActiveWindow
        }
        return InputActivityState(
            timestamp: timestamp,
            recentInputActive: !recentTimestamps.isEmpty,
            activeEventCount: recentTimestamps.count,
            latestActiveTimestamp: recentTimestamps.last
        )
    }
}

public struct InputActivityState: Codable, Equatable, Sendable {
    public var timestamp: Date
    public var recentInputActive: Bool
    public var activeEventCount: Int
    public var latestActiveTimestamp: Date?

    public init(
        timestamp: Date,
        recentInputActive: Bool,
        activeEventCount: Int,
        latestActiveTimestamp: Date?
    ) {
        self.timestamp = timestamp
        self.recentInputActive = recentInputActive
        self.activeEventCount = activeEventCount
        self.latestActiveTimestamp = latestActiveTimestamp
    }
}

