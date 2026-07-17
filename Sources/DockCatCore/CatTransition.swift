public struct CatTransition: Equatable, Sendable {
    public let previousState: CatState
    public let event: CatEvent
    public let nextState: CatState
    public let effect: CatCoordinatorEffect

    public init(
        previousState: CatState,
        event: CatEvent,
        nextState: CatState,
        effect: CatCoordinatorEffect
    ) {
        self.previousState = previousState
        self.event = event
        self.nextState = nextState
        self.effect = effect
    }
}

public enum CatTransitionRejectionReason: String, Equatable, Sendable {
    case invalidEventForState
    case alreadyPaused
    case notPaused
    case missingStateBeforePause
}

public struct CatTransitionRejection: Equatable, Sendable {
    public let currentState: CatState
    public let event: CatEvent
    public let reason: CatTransitionRejectionReason

    public init(currentState: CatState, event: CatEvent, reason: CatTransitionRejectionReason) {
        self.currentState = currentState
        self.event = event
        self.reason = reason
    }
}

public enum CatTransitionResult: Equatable, Sendable {
    case accepted(CatTransition)
    case rejected(CatTransitionRejection)

    public var transition: CatTransition? {
        guard case .accepted(let transition) = self else { return nil }
        return transition
    }
}

public struct CatRecoveryTransition: Equatable, Sendable {
    public let previousState: CatState
    public let safeState: CatState

    public init(previousState: CatState, safeState: CatState) {
        self.previousState = previousState
        self.safeState = safeState
    }
}
