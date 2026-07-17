import Foundation

/// The cat's semantic location during presentation choreography. Geometry refreshes use
/// this value instead of inferring intent from an overlay panel's current pixel position.
public enum CatLogicalPlacement: String, Equatable, Sendable {
    case home
    case travellingToPresentation
    case presentation
    case travellingHome
    case hiddenOrRecovering
}

public enum CatLogicalPlacementResolver {
    public static func resolve(
        catState: CatState,
        presentationPhase: PresentationPhase?,
        hasChoreographyTask: Bool,
        isRecovering: Bool,
        isEnabled: Bool
    ) -> CatLogicalPlacement {
        guard isEnabled, !isRecovering else { return .hiddenOrRecovering }

        // Pause changes CatState to `.paused`, while the session phase deliberately
        // remains on the interrupted operation. That phase therefore preserves travel.
        if catState == .paused {
            return placement(for: presentationPhase) ?? .home
        }

        switch catState {
        case .sleeping, .waking, .pickingUpCard, .settlingDown:
            return .home
        case .walkingToPresentation:
            return .travellingToPresentation
        case .presenting, .waitingForDismissal, .preparingNextNotification, .dismissingCard:
            return .presentation
        case .walkingHome:
            return .travellingHome
        case .paused:
            preconditionFailure("paused is handled above")
        }
    }

    private static func placement(for phase: PresentationPhase?) -> CatLogicalPlacement? {
        switch phase {
        case .waking, .pickingUp, .settling:
            return .home
        case .travellingToPresentation:
            return .travellingToPresentation
        case .presentingCard, .waitingForDismissal, .replacingCard, .dismissingCard:
            return .presentation
        case .travellingHome:
            return .travellingHome
        case .finished:
            return .home
        case nil:
            return nil
        }
    }
}
