import Foundation

public enum CatState: String, CaseIterable, Equatable, Hashable, Sendable {
    case sleeping, waking, pickingUpCard, walkingToPresentation, presenting
    case waitingForDismissal, preparingNextNotification, dismissingCard, walkingHome, settlingDown, paused
}

public enum CatEvent: String, CaseIterable, Equatable, Hashable, Sendable {
    case notificationAvailable, animationCompleted, cardPresented
    case transientExpired, userDismissed, nextNotificationAvailable, queueEmpty, cardDismissed
    case notificationUpdated, sourceDisappeared
    case pause, resume
}

public struct CatStateMachine: Sendable {
    public private(set) var state: CatState = .sleeping
    private var stateBeforePause: CatState?
    public init() {}

    init(state: CatState, stateBeforePause: CatState? = nil) {
        self.state = state
        self.stateBeforePause = stateBeforePause
    }

    public mutating func handle(_ event: CatEvent) -> CatTransitionResult {
        let result = Self.decision(from: state, event: event, stateBeforePause: stateBeforePause)
        guard case .accepted(let transition) = result else { return result }

        // Mutation happens only after the complete state/effect decision exists.
        if event == .pause { stateBeforePause = state }
        if event == .resume { stateBeforePause = nil }
        state = transition.nextState
        return result
    }

    /// Resets coordinator state after an impossible production sequence. The caller owns
    /// dropping the inconsistent active item and resetting UI before starting later work.
    @discardableResult
    public mutating func recoverToSleeping() -> CatRecoveryTransition {
        let recovery = CatRecoveryTransition(previousState: state, safeState: .sleeping)
        state = .sleeping
        stateBeforePause = nil
        return recovery
    }

    private static func decision(
        from state: CatState,
        event: CatEvent,
        stateBeforePause: CatState?
    ) -> CatTransitionResult {
        if event == .pause {
            guard state != .paused else {
                return .rejected(.init(currentState: state, event: event, reason: .alreadyPaused))
            }
            return accepted(from: state, event: event, to: .paused, effect: .pauseVisualWork)
        }

        if event == .resume {
            guard state == .paused else {
                return .rejected(.init(currentState: state, event: event, reason: .notPaused))
            }
            guard let stateBeforePause else {
                return .rejected(.init(currentState: state, event: event, reason: .missingStateBeforePause))
            }
            return accepted(from: state, event: event, to: stateBeforePause, effect: .resumePriorWork)
        }

        let decision: (CatState, CatCoordinatorEffect)?
        switch (state, event) {
        case (.sleeping, .notificationAvailable): decision = (.waking, .wake)
        case (.waking, .animationCompleted): decision = (.pickingUpCard, .pickUpCard)
        case (.pickingUpCard, .animationCompleted): decision = (.walkingToPresentation, .travelToPresentation)
        case (.walkingToPresentation, .animationCompleted): decision = (.presenting, .presentInitialCard)
        case (.presenting, .cardPresented): decision = (.waitingForDismissal, .enterWaitingState)
        case (.waitingForDismissal, .notificationUpdated): decision = (.presenting, .replaceActiveCard)
        case (.waitingForDismissal, .transientExpired),
             (.waitingForDismissal, .userDismissed),
             (.waitingForDismissal, .sourceDisappeared):
            decision = (.preparingNextNotification, .selectNextQueueAction)
        case (.preparingNextNotification, .nextNotificationAvailable): decision = (.presenting, .replaceActiveCard)
        case (.preparingNextNotification, .queueEmpty): decision = (.dismissingCard, .dismissExpandedCard)
        case (.dismissingCard, .cardDismissed): decision = (.walkingHome, .travelHome)
        case (.walkingHome, .animationCompleted): decision = (.settlingDown, .settleToSleep)
        case (.settlingDown, .animationCompleted): decision = (.sleeping, .none)
        default: decision = nil
        }

        guard let (nextState, effect) = decision else {
            return .rejected(.init(currentState: state, event: event, reason: .invalidEventForState))
        }
        return accepted(from: state, event: event, to: nextState, effect: effect)
    }

    private static func accepted(
        from previousState: CatState,
        event: CatEvent,
        to nextState: CatState,
        effect: CatCoordinatorEffect
    ) -> CatTransitionResult {
        .accepted(.init(previousState: previousState, event: event, nextState: nextState, effect: effect))
    }
}
