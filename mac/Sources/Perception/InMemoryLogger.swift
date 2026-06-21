import Foundation

public final class InMemoryLogger: Logging, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LogRecord] = []

    public init() {}

    public func log(
        _ level: LogLevel,
        _ message: String,
        module: String,
        traceId: String?,
        metadata: [String: String] = [:]
    ) {
        let record = LogRecord(
            level: level,
            message: message,
            module: module,
            traceId: traceId,
            metadata: metadata
        )
        lock.withLock {
            storage.append(record)
        }
    }

    public var records: [LogRecord] {
        lock.withLock {
            storage
        }
    }

    public func clear() {
        lock.withLock {
            storage.removeAll()
        }
    }
}

