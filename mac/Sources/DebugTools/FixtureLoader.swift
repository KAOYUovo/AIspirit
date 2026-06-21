import Foundation
import Perception

public struct FixtureLoader: Sendable {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder? = nil) {
        self.decoder = decoder ?? JSONDecoder.perceptionFixture
    }

    public func loadScenario(
        from fileURL: URL,
        id: String? = nil,
        name: String? = nil,
        description: String = ""
    ) throws -> ReplayScenario {
        let data = try Data(contentsOf: fileURL)
        return try loadScenario(
            fromJSONLData: data,
            id: id ?? fileURL.deletingPathExtension().lastPathComponent,
            name: name ?? fileURL.deletingPathExtension().lastPathComponent,
            description: description
        )
    }

    public func loadScenario(
        fromJSONLData data: Data,
        id: String,
        name: String,
        description: String = ""
    ) throws -> ReplayScenario {
        let text = String(decoding: data, as: UTF8.self)
        let events = try text
            .split(whereSeparator: \.isNewline)
            .map { line in
                try decoder.decode(PerceptionDiagnosticEvent.self, from: Data(line.utf8))
            }
        return ReplayScenario(id: id, name: name, description: description, events: events)
    }
}

