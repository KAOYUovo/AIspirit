import Foundation
import Perception

public struct FixtureWriter: Sendable {
    private let encoder: JSONEncoder

    public init(encoder: JSONEncoder? = nil) {
        self.encoder = encoder ?? JSONEncoder.perceptionFixture
    }

    public func write(_ scenario: ReplayScenario, to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try jsonlData(for: scenario)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func jsonlData(for scenario: ReplayScenario) throws -> Data {
        var data = Data()
        for event in scenario.events {
            data.append(try encoder.encode(event))
            data.append(0x0A)
        }
        return data
    }
}

extension JSONEncoder {
    static var perceptionFixture: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

extension JSONDecoder {
    static var perceptionFixture: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

