import Foundation

/// The only visible responses a geometry refresh may request. None of these actions
/// mutates presentation state, notification ownership, or transient timing.
public enum PlacementRefreshAction: Equatable, Sendable {
    case moveToHome
    case retargetPresentationTravel
    case moveToPresentation
    case retargetHomeTravel
    case preserveRecoveryVisuals
}

public enum PlacementRefreshPolicy {
    public static func action(for placement: CatLogicalPlacement) -> PlacementRefreshAction {
        switch placement {
        case .home: .moveToHome
        case .travellingToPresentation: .retargetPresentationTravel
        case .presentation: .moveToPresentation
        case .travellingHome: .retargetHomeTravel
        case .hiddenOrRecovering: .preserveRecoveryVisuals
        }
    }

    public static func availabilityAction(
        hasResolvedPlacement: Bool,
        hasLastValidPlacement: Bool
    ) -> PlacementAvailabilityAction {
        if hasResolvedPlacement { return .applyResolvedPlacement }
        return hasLastValidPlacement ? .retainLastValidPlacement : .awaitFirstValidPlacement
    }
}

public enum PlacementAvailabilityAction: Equatable, Sendable {
    case applyResolvedPlacement
    case retainLastValidPlacement
    case awaitFirstValidPlacement
}
