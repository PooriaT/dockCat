import Foundation

public enum PresentationAnimationResult: Equatable, Sendable { case completed, cancelled }

public enum PresentationChoreographyStep: Equatable, Sendable {
    case showMiniCard
    case travelToPresentation
    case presentExpandedCard
    case hideMiniCard
    case enterWaiting
    case scheduleTransientTimeout
    case doNotScheduleTimeout
    case requestCardDismissal
    case dismissExpandedCard
    case cardDismissed
    case replaceExpandedCard
    case walkHome
    case settle
    case sleep
}

public enum CardPresentationKind: Equatable, Sendable { case transient, persistent }

public enum PresentationChoreography {
    public static func presentationSteps(kind: CardPresentationKind) -> [PresentationChoreographyStep] {
        [.showMiniCard, .travelToPresentation, .presentExpandedCard, .hideMiniCard, .enterWaiting] + (kind == .transient ? [.scheduleTransientTimeout] : [.doNotScheduleTimeout])
    }

    public static func dismissalSteps(hasQueuedReplacement: Bool, remainInPlace: Bool, nextKind: CardPresentationKind?) -> [PresentationChoreographyStep] {
        if hasQueuedReplacement && remainInPlace {
            return [.requestCardDismissal, .replaceExpandedCard, .enterWaiting] + (nextKind == .transient ? [.scheduleTransientTimeout] : [.doNotScheduleTimeout])
        }
        return [.requestCardDismissal, .dismissExpandedCard, .cardDismissed, .walkHome, .settle, .sleep]
    }

    public static func shouldAcceptPresentationCompletion(_ result: PresentationAnimationResult) -> Bool { result == .completed }
}
