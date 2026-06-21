import Foundation

public struct AttentionStateInput: Equatable, Sendable {
    public var previousState: AttentionState
    public var inputActivity: InputActivityState
    public var eventKind: AttentionEventKind
    public var secondsSinceEngaged: TimeInterval?
    public var intendedPetAction: PetActionIntent?

    public init(
        previousState: AttentionState = .observing,
        inputActivity: InputActivityState,
        eventKind: AttentionEventKind = .passive,
        secondsSinceEngaged: TimeInterval? = nil,
        intendedPetAction: PetActionIntent? = nil
    ) {
        self.previousState = previousState
        self.inputActivity = inputActivity
        self.eventKind = eventKind
        self.secondsSinceEngaged = secondsSinceEngaged
        self.intendedPetAction = intendedPetAction
    }
}

public struct AttentionStateMachineResult: Equatable, Sendable {
    public var state: AttentionState
    public var petActions: [PetActionDTO]

    public init(state: AttentionState, petActions: [PetActionDTO]) {
        self.state = state
        self.petActions = petActions
    }
}

public struct AttentionStateMachine: Sendable {
    private let parameters: PerceptionParameters
    private let busyInputEventThreshold: Int

    public init(parameters: PerceptionParameters = .defaults, busyInputEventThreshold: Int = 3) {
        self.parameters = parameters
        self.busyInputEventThreshold = busyInputEventThreshold
    }

    public func evaluate(_ input: AttentionStateInput) -> AttentionStateMachineResult {
        let state = nextState(for: input)
        return AttentionStateMachineResult(
            state: state,
            petActions: petActions(for: state, intendedAction: input.intendedPetAction)
        )
    }

    private func nextState(for input: AttentionStateInput) -> AttentionState {
        if input.eventKind == .userInvokedPet {
            return .engaged
        }

        if input.previousState == .engaged {
            if let secondsSinceEngaged = input.secondsSinceEngaged,
               secondsSinceEngaged > parameters.engagedTimeout {
                return .observing
            }
            return .engaged
        }

        if input.inputActivity.recentInputActive
            && input.inputActivity.activeEventCount >= busyInputEventThreshold {
            return .busy
        }

        return .observing
    }

    private func petActions(for state: AttentionState, intendedAction: PetActionIntent?) -> [PetActionDTO] {
        guard state == .busy, intendedAction == .longBubble else {
            return []
        }

        return [
            PetActionDTO(type: .suppressBubble, payload: ["reason": "attentionState=busy"])
        ]
    }
}
