import Foundation

public struct PerceptionParameters: Codable, Equatable, Sendable {
    public var normalTickInterval: TimeInterval
    public var normalMinAIInterval: TimeInterval
    public var coWatchingMinAIInterval: TimeInterval
    public var lowPowerTickInterval: TimeInterval
    public var lowPowerMinAIInterval: TimeInterval
    public var forceRefreshInterval: TimeInterval
    public var idleThreshold: TimeInterval
    public var inputActiveWindow: TimeInterval
    public var instantInputThreshold: TimeInterval
    public var dHashGlobalThreshold: Int
    public var dHashRegionThreshold: Int
    public var coWatchEnterSustain: TimeInterval
    public var coWatchExitSustain: TimeInterval
    public var engagedTimeout: TimeInterval
    public var thermalTrigger: ThermalTrigger
    public var batteryLevelTrigger: Double
    public var vlmTimeout: TimeInterval
    public var vlmMaxPerHour: Int
    public var imageMaxEdge: Int
    public var imageJPEGQuality: Double

    public init(
        normalTickInterval: TimeInterval = 4,
        normalMinAIInterval: TimeInterval = 15,
        coWatchingMinAIInterval: TimeInterval = 10,
        lowPowerTickInterval: TimeInterval = 12,
        lowPowerMinAIInterval: TimeInterval = 60,
        forceRefreshInterval: TimeInterval = 120,
        idleThreshold: TimeInterval = 60,
        inputActiveWindow: TimeInterval = 30,
        instantInputThreshold: TimeInterval = 5,
        dHashGlobalThreshold: Int = 10,
        dHashRegionThreshold: Int = 8,
        coWatchEnterSustain: TimeInterval = 5,
        coWatchExitSustain: TimeInterval = 10,
        engagedTimeout: TimeInterval = 30,
        thermalTrigger: ThermalTrigger = .serious,
        batteryLevelTrigger: Double = 0.2,
        vlmTimeout: TimeInterval = 20,
        vlmMaxPerHour: Int = 120,
        imageMaxEdge: Int = 1536,
        imageJPEGQuality: Double = 0.6
    ) {
        self.normalTickInterval = normalTickInterval
        self.normalMinAIInterval = normalMinAIInterval
        self.coWatchingMinAIInterval = coWatchingMinAIInterval
        self.lowPowerTickInterval = lowPowerTickInterval
        self.lowPowerMinAIInterval = lowPowerMinAIInterval
        self.forceRefreshInterval = forceRefreshInterval
        self.idleThreshold = idleThreshold
        self.inputActiveWindow = inputActiveWindow
        self.instantInputThreshold = instantInputThreshold
        self.dHashGlobalThreshold = dHashGlobalThreshold
        self.dHashRegionThreshold = dHashRegionThreshold
        self.coWatchEnterSustain = coWatchEnterSustain
        self.coWatchExitSustain = coWatchExitSustain
        self.engagedTimeout = engagedTimeout
        self.thermalTrigger = thermalTrigger
        self.batteryLevelTrigger = batteryLevelTrigger
        self.vlmTimeout = vlmTimeout
        self.vlmMaxPerHour = vlmMaxPerHour
        self.imageMaxEdge = imageMaxEdge
        self.imageJPEGQuality = imageJPEGQuality
    }

    public static let defaults = PerceptionParameters()
}

public enum ThermalTrigger: String, Codable, Comparable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    public static func < (lhs: ThermalTrigger, rhs: ThermalTrigger) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .nominal:
            return 0
        case .fair:
            return 1
        case .serious:
            return 2
        case .critical:
            return 3
        }
    }
}
