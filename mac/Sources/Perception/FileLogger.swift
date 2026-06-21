import Foundation

public final class FileLogger: Logging, @unchecked Sendable {
    private let writer: LogFileWriter
    private let minimumLevel: LogLevel
    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var logTasks: [Task<Void, Never>] = []

    public init(
        rootDirectory: URL,
        fileName: String = "app.log",
        minimumLevel: LogLevel = .debug,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.writer = LogFileWriter(rootDirectory: rootDirectory, fileName: fileName)
        self.minimumLevel = minimumLevel
        self.clock = clock
    }

    public func log(
        _ level: LogLevel,
        _ message: String,
        module: String,
        traceId: String?,
        metadata: [String: String] = [:]
    ) {
        let task = Task { [writer, minimumLevel, clock] in
            guard level >= minimumLevel else {
                return
            }
            await writer.append(
                timestamp: clock(),
                level: level,
                message: message,
                module: module,
                traceId: traceId,
                metadata: metadata
            )
        }
        lock.withLock {
            logTasks.append(task)
        }
    }

    public func flush() async {
        let tasks = lock.withLock {
            let tasks = logTasks
            logTasks.removeAll()
            return tasks
        }
        for task in tasks {
            await task.value
        }
        await writer.flush()
    }

    public var failureCount: Int {
        get async {
            await writer.failureCount
        }
    }
}

private actor LogFileWriter {
    private let rootDirectory: URL
    private let fileName: String
    private var pendingTasks = 0
    private(set) var failureCount = 0

    init(rootDirectory: URL, fileName: String) {
        self.rootDirectory = rootDirectory
        self.fileName = fileName
    }

    func append(
        timestamp: Date,
        level: LogLevel,
        message: String,
        module: String,
        traceId: String?,
        metadata: [String: String]
    ) {
        pendingTasks += 1
        defer { pendingTasks -= 1 }

        do {
            let directory = rootDirectory.appendingPathComponent(Self.dayStamp(for: timestamp), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(fileName)
            let line = Self.formatLine(
                timestamp: timestamp,
                level: level,
                message: message,
                module: module,
                traceId: traceId,
                metadata: metadata
            )
            let data = Data((line + "\n").utf8)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: [.atomic])
            }
        } catch {
            failureCount += 1
        }
    }

    func flush() async {
        while pendingTasks > 0 {
            await Task.yield()
        }
    }

    private static func formatLine(
        timestamp: Date,
        level: LogLevel,
        message: String,
        module: String,
        traceId: String?,
        metadata: [String: String]
    ) -> String {
        var line = "\(timestampStamp(for: timestamp)) [\(level.displayName)] [\(module)] [\(traceId ?? "-")] \(message)"
        let metadataText = metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if !metadataText.isEmpty {
            line += "  \(metadataText)"
        }
        return line
    }

    private static func timestampStamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private static func dayStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
