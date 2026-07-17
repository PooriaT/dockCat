public enum CatCoordinatorEffect: String, CaseIterable, Equatable, Sendable {
    case wake
    case pickUpCard
    case travelToPresentation
    case presentInitialCard
    case enterWaitingState
    case replaceActiveCard
    case selectNextQueueAction
    case dismissExpandedCard
    case travelHome
    case settleToSleep
    case pauseVisualWork
    case resumePriorWork
    case none
}
