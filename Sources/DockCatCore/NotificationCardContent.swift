import Foundation

/// Privacy-safe queue metadata for the card that is currently being presented.
/// The current item is never included in `pendingCount`.
public struct CardQueueContext: Equatable, Sendable {
    public static let empty = CardQueueContext(pendingCount: 0, isDeliveryPaused: false)

    public let pendingCount: Int
    public let isDeliveryPaused: Bool

    public init(pendingCount: Int, isDeliveryPaused: Bool) {
        self.pendingCount = max(0, pendingCount)
        self.isDeliveryPaused = isDeliveryPaused
    }

    public var isVisible: Bool { pendingCount > 0 || isDeliveryPaused }

    /// Deterministic English copy. Full localization is intentionally deferred.
    public var visibleText: String? {
        guard isVisible else { return nil }
        if pendingCount == 0 { return "Delivery paused" }
        if isDeliveryPaused {
            let waiting = pendingCount == 1
                ? "1 additional notification waiting"
                : "\(pendingCount) additional notifications waiting"
            return "\(waiting) · delivery paused"
        }
        let count = pendingCount == 1
            ? "1 more notification"
            : "\(pendingCount) more notifications"
        return count
    }
}

/// Immutable card input. URLs and mutable queue/preferences objects deliberately stay
/// outside this semantic model.
public struct NotificationCardContent: Equatable, Sendable {
    public let notificationID: UUID
    public let sourceName: String
    public let title: String
    public let message: String
    public let presentation: CardPresentationKind
    public let hasOpenAction: Bool
    public let canDismiss: Bool
    public let queueContext: CardQueueContext

    public init(
        notificationID: UUID,
        sourceName: String,
        title: String,
        message: String,
        presentation: CardPresentationKind,
        hasOpenAction: Bool,
        canDismiss: Bool,
        queueContext: CardQueueContext
    ) {
        self.notificationID = notificationID
        self.sourceName = sourceName
        self.title = title
        self.message = message
        self.presentation = presentation
        self.hasOpenAction = hasOpenAction
        self.canDismiss = canDismiss
        self.queueContext = queueContext
    }
}
