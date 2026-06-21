import Foundation

public enum CollectorFailure: Error, Equatable, Sendable {
    case unavailable(String)
    case permissionDenied(String)
    case captureFailed(String)
    case transcriptionFailed(String)
    case networkDisabled
}

public struct FrontAppSnapshot: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleIdentifier: String?
    public var processIdentifier: Int?
    public var windowTitles: [String]
    public var targetDisplayID: UInt32?

    public init(
        appName: String,
        bundleIdentifier: String? = nil,
        processIdentifier: Int? = nil,
        windowTitles: [String] = [],
        targetDisplayID: UInt32? = nil
    ) {
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.windowTitles = windowTitles
        self.targetDisplayID = targetDisplayID
    }

    public static let unknown = FrontAppSnapshot(appName: "unknown")
}

public struct CapturedFrame: Codable, Equatable, Sendable {
    public var id: String
    public var timestamp: Date
    public var width: Int
    public var height: Int
    public var displayID: UInt32?
    public var imageData: Data?

    public init(
        id: String,
        timestamp: Date,
        width: Int,
        height: Int,
        displayID: UInt32? = nil,
        imageData: Data? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.displayID = displayID
        self.imageData = imageData
    }
}

public enum ScreenState: String, Codable, Equatable, Sendable {
    case active
    case locked
    case screenSleeping
    case systemSleeping
    case unknown
}

public struct PowerSnapshot: Codable, Equatable, Sendable {
    public var powerState: PowerState
    public var thermalState: ThermalTrigger

    public init(powerState: PowerState, thermalState: ThermalTrigger) {
        self.powerState = powerState
        self.thermalState = thermalState
    }

    public static let nominal = PowerSnapshot(
        powerState: PowerState(batteryLevel: nil, isCharging: true, isLowPowerMode: false),
        thermalState: .nominal
    )
}

public struct AudioChunk: Codable, Equatable, Sendable {
    public var id: String
    public var timestampStart: Date
    public var timestampEnd: Date
    public var sampleRate: Int
    public var channelCount: Int
    public var pcmData: Data

    public init(
        id: String,
        timestampStart: Date,
        timestampEnd: Date,
        sampleRate: Int,
        channelCount: Int,
        pcmData: Data
    ) {
        self.id = id
        self.timestampStart = timestampStart
        self.timestampEnd = timestampEnd
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.pcmData = pcmData
    }
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var text: String
    public var confidence: Double?
    public var timestampStart: Date?
    public var timestampEnd: Date?

    public init(text: String, confidence: Double? = nil, timestampStart: Date? = nil, timestampEnd: Date? = nil) {
        self.text = text
        self.confidence = confidence
        self.timestampStart = timestampStart
        self.timestampEnd = timestampEnd
    }
}

public struct WebMetadataResult: Codable, Equatable, Sendable {
    public var query: String
    public var title: String
    public var summary: String
    public var sourceURL: URL?

    public init(query: String, title: String, summary: String, sourceURL: URL? = nil) {
        self.query = query
        self.title = title
        self.summary = summary
        self.sourceURL = sourceURL
    }
}

