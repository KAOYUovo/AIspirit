import Foundation
import Perception

public struct PerceptionReplayConfig: Codable, Equatable, Sendable {
    public var overrideFeatureFlags: PerceptionFeatureFlags?
    public var speed: ReplaySpeed
    public var startIndex: Int?
    public var endIndex: Int?

    public init(
        overrideFeatureFlags: PerceptionFeatureFlags? = nil,
        speed: ReplaySpeed = .fast,
        startIndex: Int? = nil,
        endIndex: Int? = nil
    ) {
        self.overrideFeatureFlags = overrideFeatureFlags
        self.speed = speed
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

public enum ReplaySpeed: String, Codable, Sendable {
    case realtime
    case fast
    case step
}

public struct ReplayResult: Codable, Equatable, Sendable {
    public var scenarioID: String
    public var totalEvents: Int
    public var analyzedCount: Int
    public var skippedCount: Int
    public var fallbackCount: Int
    public var decisions: [GateDecision]
    public var petActions: [[PetActionDTO]]
    public var effectiveFeatureFlags: [PerceptionFeatureFlags]
    public var mismatches: [ReplayMismatch]

    public init(
        scenarioID: String,
        totalEvents: Int,
        analyzedCount: Int,
        skippedCount: Int,
        fallbackCount: Int,
        decisions: [GateDecision],
        petActions: [[PetActionDTO]],
        effectiveFeatureFlags: [PerceptionFeatureFlags],
        mismatches: [ReplayMismatch]
    ) {
        self.scenarioID = scenarioID
        self.totalEvents = totalEvents
        self.analyzedCount = analyzedCount
        self.skippedCount = skippedCount
        self.fallbackCount = fallbackCount
        self.decisions = decisions
        self.petActions = petActions
        self.effectiveFeatureFlags = effectiveFeatureFlags
        self.mismatches = mismatches
    }
}

public struct ReplayMismatch: Codable, Equatable, Sendable {
    public var eventID: String
    public var expected: String
    public var actual: String
    public var reason: String

    public init(eventID: String, expected: String, actual: String, reason: String) {
        self.eventID = eventID
        self.expected = expected
        self.actual = actual
        self.reason = reason
    }
}

