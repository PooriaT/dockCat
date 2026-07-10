import Foundation

public enum CatState: String, Equatable, Sendable {
    case sleeping, waking, pickingUpCard, walkingToPresentation, presenting
    case waitingForDismissal, preparingNextNotification, walkingHome, settlingDown, paused
}

public enum CatEvent: Equatable, Sendable {
    case notificationAvailable, animationCompleted, cardPresented
    case transientExpired, userDismissed, nextNotificationAvailable, queueEmpty
    case pause, resume
}

public struct CatStateMachine: Sendable {
    public private(set) var state: CatState = .sleeping
    private var stateBeforePause: CatState?
    public init() {}

    @discardableResult
    public mutating func handle(_ event: CatEvent) -> Bool {
        if event == .pause, state != .paused {
            stateBeforePause = state; state = .paused; return true
        }
        if event == .resume, state == .paused {
            state = stateBeforePause ?? .sleeping; stateBeforePause = nil; return true
        }
        let next: CatState?
        switch (state, event) {
        case (.sleeping, .notificationAvailable): next = .waking
        case (.waking, .animationCompleted): next = .pickingUpCard
        case (.pickingUpCard, .animationCompleted): next = .walkingToPresentation
        case (.walkingToPresentation, .animationCompleted): next = .presenting
        case (.presenting, .cardPresented): next = .waitingForDismissal
        case (.waitingForDismissal, .transientExpired), (.waitingForDismissal, .userDismissed): next = .preparingNextNotification
        case (.preparingNextNotification, .nextNotificationAvailable): next = .presenting
        case (.preparingNextNotification, .queueEmpty): next = .walkingHome
        case (.walkingHome, .animationCompleted): next = .settlingDown
        case (.settlingDown, .animationCompleted): next = .sleeping
        default: next = nil
        }
        guard let next else { return false }
        state = next
        return true
    }
}
