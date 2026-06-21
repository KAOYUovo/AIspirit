import Foundation

public actor PerceptionDiagnostics {
    private let enabled: Bool
    private let rootDirectory: URL
    private let fileManager: FileManager
    private var writers: [String: JSONLWriter] = [:]

    public init(
        enabled: Bool,
        rootDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.enabled = enabled
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    public func record(_ event: PerceptionDiagnosticEvent) async {
        guard enabled else {
            return
        }
        let writer = writer(for: event.timestamp)
        await writer.append(event)
    }

    public func flush() async {
        for writer in writers.values {
            await writer.flush()
        }
    }

    public func exportPackage() async throws -> URL {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        return rootDirectory
    }

    public func clearOldLogs(olderThan days: Int, now: Date = Date()) async {
        guard days >= 0 else {
            return
        }
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 24 * 60 * 60)
        let perceptionRoot = rootDirectory.appendingPathComponent("perception", isDirectory: true)

        guard let entries = try? fileManager.contentsOfDirectory(
            at: perceptionRoot,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for entry in entries where entry.hasDirectoryPath {
            guard let date = Self.dayFormatter.date(from: entry.lastPathComponent), date < cutoff else {
                continue
            }
            try? fileManager.removeItem(at: entry)
            writers.removeValue(forKey: entry.lastPathComponent)
        }
    }

    private func writer(for timestamp: Date) -> JSONLWriter {
        let day = Self.dayStamp(for: timestamp)
        if let writer = writers[day] {
            return writer
        }

        let fileURL = rootDirectory
            .appendingPathComponent("perception", isDirectory: true)
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent("perception.jsonl")
        let writer = JSONLWriter(fileURL: fileURL)
        writers[day] = writer
        return writer
    }

    private static func dayStamp(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

