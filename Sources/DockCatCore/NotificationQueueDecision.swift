import Foundation

public typealias NotificationQueueRevision = UInt64

/// Privacy-safe, immutable queue state for reconciliation and diagnostics.
/// Notification content and pending storage are intentionally not exposed.
public struct NotificationQueueSnapshot: Equatable, Sendable {
    public let isPaused: Bool
    public let currentID: UUID?
    public let pendingCount: Int
    public let limit: Int
    public let revision: NotificationQueueRevision
    public let recentCompletionCount: Int
    public let recentCompletionCapacity: Int

    public var count: Int { pendingCount + (currentID == nil ? 0 : 1) }
    public var cardQueueContext: CardQueueContext {
        .init(pendingCount: pendingCount, isDeliveryPaused: isPaused)
    }

    public func matches(projectedCurrent: DockCatNotification?) -> Bool {
        currentID == projectedCurrent?.id
    }
}

public enum NotificationQueueEnqueueResult: Equatable, Sendable {
    case accepted(revision: NotificationQueueRevision)
    case duplicate(revision: NotificationQueueRevision)
    case full(revision: NotificationQueueRevision)

    public var revision: NotificationQueueRevision {
        switch self {
        case .accepted(let revision), .duplicate(let revision), .full(let revision): revision
        }
    }

    public var wasAccepted: Bool {
        if case .accepted = self { true } else { false }
    }
}

public enum NotificationQueueClaimResult: Equatable, Sendable {
    case promoted(DockCatNotification, revision: NotificationQueueRevision)
    case current(DockCatNotification, revision: NotificationQueueRevision)
    case paused(current: DockCatNotification?, pendingCount: Int, revision: NotificationQueueRevision)
    case idle(revision: NotificationQueueRevision)

    public var revision: NotificationQueueRevision {
        switch self {
        case .promoted(_, let revision), .current(_, let revision),
             .paused(_, _, let revision), .idle(let revision): revision
        }
    }
}

public enum NotificationQueueCompletionPolicy: Equatable, Sendable {
    case advanceImmediately
    case leavePendingForLater
}

public enum NotificationQueueCompletionResult: Equatable, Sendable {
    case advanced(completed: DockCatNotification, next: DockCatNotification, revision: NotificationQueueRevision)
    case completedAndIdle(completed: DockCatNotification, revision: NotificationQueueRevision)
    case completedWithPending(completed: DockCatNotification, pendingCount: Int, revision: NotificationQueueRevision)
    case pausedAfterCompletion(completed: DockCatNotification, pendingCount: Int, revision: NotificationQueueRevision)
    case noCurrent(revision: NotificationQueueRevision)

    public var revision: NotificationQueueRevision {
        switch self {
        case .advanced(_, _, let revision), .completedAndIdle(_, let revision),
             .completedWithPending(_, _, let revision), .pausedAfterCompletion(_, _, let revision),
             .noCurrent(let revision): revision
        }
    }
}

public enum NotificationQueuePauseResult: Equatable, Sendable {
    case changed(isPaused: Bool, currentID: UUID?, pendingCount: Int, revision: NotificationQueueRevision)
    case unchanged(isPaused: Bool, currentID: UUID?, pendingCount: Int, revision: NotificationQueueRevision)

    public var isPaused: Bool {
        switch self {
        case .changed(let value, _, _, _), .unchanged(let value, _, _, _): value
        }
    }

    public var revision: NotificationQueueRevision {
        switch self {
        case .changed(_, _, _, let revision), .unchanged(_, _, _, let revision): revision
        }
    }

    public var currentID: UUID? {
        switch self {
        case .changed(_, let id, _, _), .unchanged(_, let id, _, _): id
        }
    }

    public var pendingCount: Int {
        switch self {
        case .changed(_, _, let count, _), .unchanged(_, _, let count, _): count
        }
    }
}

public enum NotificationQueueLimitResult: Equatable, Sendable {
    case changed(previous: Int, current: Int, revision: NotificationQueueRevision)
    case unchanged(current: Int, revision: NotificationQueueRevision)

    public var revision: NotificationQueueRevision {
        switch self {
        case .changed(_, _, let revision), .unchanged(_, let revision): revision
        }
    }
}

public struct NotificationQueueClearResult: Equatable, Sendable {
    public let removedCurrentID: UUID?
    public let removedPendingCount: Int
    public let revision: NotificationQueueRevision
    public let didChange: Bool

    public init(
        removedCurrentID: UUID?,
        removedPendingCount: Int,
        revision: NotificationQueueRevision,
        didChange: Bool
    ) {
        self.removedCurrentID = removedCurrentID
        self.removedPendingCount = removedPendingCount
        self.revision = revision
        self.didChange = didChange
    }
}

public enum NotificationQueueExternalLocation: Equatable, Sendable {
    case current
    case pending(index: Int)
}

public enum NotificationQueueExternalMutationResult: Equatable, Sendable {
    case inserted(notification: DockCatNotification, index: Int, revision: NotificationQueueRevision)
    case updatedCurrent(notification: DockCatNotification, revision: NotificationQueueRevision)
    case updatedPending(notification: DockCatNotification, index: Int, revision: NotificationQueueRevision)
    case unchangedCurrent(notification: DockCatNotification, revision: NotificationQueueRevision)
    case unchangedPending(notification: DockCatNotification, index: Int, revision: NotificationQueueRevision)
    case removedCurrent(notification: DockCatNotification, pendingCount: Int, revision: NotificationQueueRevision)
    case removedPending(notification: DockCatNotification, index: Int, revision: NotificationQueueRevision)
    case notFound(revision: NotificationQueueRevision)
    case duplicate(revision: NotificationQueueRevision)
    case full(revision: NotificationQueueRevision)

    public var revision: NotificationQueueRevision {
        switch self {
        case .inserted(_, _, let revision), .updatedCurrent(_, let revision),
             .updatedPending(_, _, let revision), .unchangedCurrent(_, let revision),
             .unchangedPending(_, _, let revision), .removedCurrent(_, _, let revision),
             .removedPending(_, _, let revision), .notFound(let revision),
             .duplicate(let revision), .full(let revision): revision
        }
    }

    public var updatedCurrent: DockCatNotification? {
        switch self {
        case .updatedCurrent(let notification, _), .unchangedCurrent(let notification, _): notification
        default: nil
        }
    }

    public var removedCurrent: DockCatNotification? {
        guard case .removedCurrent(let notification, _, _) = self else { return nil }
        return notification
    }

    public var requiresOrderedDismissal: Bool { removedCurrent != nil }

    public var didMutate: Bool {
        switch self {
        case .inserted, .updatedCurrent, .updatedPending, .removedCurrent, .removedPending:
            true
        case .unchangedCurrent, .unchangedPending, .notFound, .duplicate, .full:
            false
        }
    }
}
