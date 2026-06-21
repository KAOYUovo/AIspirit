import Foundation

public actor JSONLWriter {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private var pendingWrites = 0
    public private(set) var failureCount = 0

    public init(fileURL: URL, encoder: JSONEncoder? = nil) {
        self.fileURL = fileURL
        self.encoder = encoder ?? JSONEncoder.perceptionJSONL
    }

    public func append<T: Encodable>(_ value: T) async {
        pendingWrites += 1
        defer { pendingWrites -= 1 }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(value)
            var line = data
            line.append(0x0A)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: fileURL, options: [.atomic])
            }
        } catch {
            failureCount += 1
        }
    }

    public func flush() async {
        while pendingWrites > 0 {
            await Task.yield()
        }
    }
}

extension JSONEncoder {
    static var perceptionJSONL: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
