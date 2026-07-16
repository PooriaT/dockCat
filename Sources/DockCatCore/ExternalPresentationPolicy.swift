import Foundation

public enum ExternalPresentationClassification: Equatable, Sendable {
    case transient(reason: String)
    case persistent(reason: String)
    case ambiguous(reason: String)
}

/// A deterministic, best-effort policy based only on structural evidence.
public struct ExternalPresentationPolicy: Sendable {
    public init() {}

    public func classify(_ candidate: AccessibilityNotificationCandidate) -> ExternalPresentationClassification {
        let hasAction = candidate.actions.contains { action in
            !action.supportedActions.isEmpty || action.identifier != nil
        }
        if candidate.structuralKind == .alert || hasAction {
            return .persistent(reason: "alert or visible action control")
        }
        if candidate.structuralKind == .banner {
            return .transient(reason: "simple banner structure")
        }
        return .ambiguous(reason: "insufficient structural evidence")
    }
}
