import Foundation

public enum LogLevel: Int, Codable, Comparable, Sendable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO "
        case .warning:
            return "WARN "
        case .error:
            return "ERROR"
        }
    }
}

public protocol Logging: Sendable {
    func log(
        _ level: LogLevel,
        _ message: String,
        module: String,
        traceId: String?,
        metadata: [String: String]
    )
}

public struct LogRecord: Codable, Equatable, Sendable {
    public var level: LogLevel
    public var message: String
    public var module: String
    public var traceId: String?
    public var metadata: [String: String]

    public init(
        level: LogLevel,
        message: String,
        module: String,
        traceId: String?,
        metadata: [String: String]
    ) {
        self.level = level
        self.message = message
        self.module = module
        self.traceId = traceId
        self.metadata = metadata
    }
}

