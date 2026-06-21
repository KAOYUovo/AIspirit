import Foundation
import Perception

public struct AttentionStateFixtureCase: Codable, Equatable, Sendable {
    public var id: String
    public var description: String
    public var previousState: AttentionState
    public var inputActivity: InputActivityState
    public var eventKind: AttentionEventKind
    public var secondsSinceEngaged: TimeInterval?
    public var intendedPetAction: PetActionIntent?
    public var expectedState: AttentionState
    public var expectedPetActions: [PetActionDTO]

    public init(
        id: String,
        description: String,
        previousState: AttentionState = .observing,
        inputActivity: InputActivityState,
        eventKind: AttentionEventKind = .passive,
        secondsSinceEngaged: TimeInterval? = nil,
        intendedPetAction: PetActionIntent? = nil,
        expectedState: AttentionState,
        expectedPetActions: [PetActionDTO] = []
    ) {
        self.id = id
        self.description = description
        self.previousState = previousState
        self.inputActivity = inputActivity
        self.eventKind = eventKind
        self.secondsSinceEngaged = secondsSinceEngaged
        self.intendedPetAction = intendedPetAction
        self.expectedState = expectedState
        self.expectedPetActions = expectedPetActions
    }
}

public enum AttentionStateFixtureFactory {
    public static func requiredCases(anchor: Date = Date(timeIntervalSince1970: 1_780_010_000)) -> [AttentionStateFixtureCase] {
        [
            AttentionStateFixtureCase(
                id: "high-recent-input-busy",
                description: "high recent input activity -> busy",
                inputActivity: InputActivityState(
                    timestamp: anchor,
                    recentInputActive: true,
                    activeEventCount: 3,
                    latestActiveTimestamp: anchor
                ),
                expectedState: .busy
            ),
            AttentionStateFixtureCase(
                id: "low-input-stable-observing",
                description: "low input + stable app -> observing",
                previousState: .busy,
                inputActivity: InputActivityState(
                    timestamp: anchor,
                    recentInputActive: true,
                    activeEventCount: 1,
                    latestActiveTimestamp: anchor.addingTimeInterval(-10)
                ),
                expectedState: .observing
            ),
            AttentionStateFixtureCase(
                id: "user-invoked-engaged",
                description: "user invoked pet -> engaged",
                inputActivity: InputActivityState(
                    timestamp: anchor,
                    recentInputActive: false,
                    activeEventCount: 0,
                    latestActiveTimestamp: nil
                ),
                eventKind: .userInvokedPet,
                expectedState: .engaged
            ),
            AttentionStateFixtureCase(
                id: "engaged-timeout-observing",
                description: "engaged timeout -> observing",
                previousState: .engaged,
                inputActivity: InputActivityState(
                    timestamp: anchor,
                    recentInputActive: false,
                    activeEventCount: 0,
                    latestActiveTimestamp: nil
                ),
                secondsSinceEngaged: 30.1,
                expectedState: .observing
            ),
            AttentionStateFixtureCase(
                id: "busy-suppresses-long-bubble",
                description: "busy suppresses long bubble",
                previousState: .busy,
                inputActivity: InputActivityState(
                    timestamp: anchor,
                    recentInputActive: true,
                    activeEventCount: 4,
                    latestActiveTimestamp: anchor
                ),
                intendedPetAction: .longBubble,
                expectedState: .busy,
                expectedPetActions: [
                    PetActionDTO(type: .suppressBubble, payload: ["reason": "attentionState=busy"])
                ]
            )
        ]
    }
}
