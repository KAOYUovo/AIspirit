import Foundation
import Perception

public struct ReplayScenario: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var events: [PerceptionDiagnosticEvent]

    public init(
        id: String,
        name: String,
        description: String,
        events: [PerceptionDiagnosticEvent]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.events = events
    }
}

