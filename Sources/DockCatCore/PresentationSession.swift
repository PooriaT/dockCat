import Foundation

public struct PresentationSessionID: Hashable, Sendable {
    public let generation: UInt64
    public let notificationID: UUID

    public init(generation: UInt64, notificationID: UUID) {
        self.generation = generation
        self.notificationID = notificationID
    }
}

public enum PresentationPhase: String, Equatable, Sendable {
    case waking
    case pickingUp
    case travellingToPresentation
    case presentingCard
    case waitingForDismissal
    case replacingCard
    case dismissingCard
    case travellingHome
    case settling
    case finished
}

public enum PresentationChildTask: Hashable, Sendable {
    case choreography
    case timeout
}

public enum DismissalCause: String, Equatable, Sendable {
    case userClose
    case transientExpiry
    case sourceDisappearance
    case globalDisable
    case sourceShutdown
    case permissionLoss
    case recovery
    case queueRemoval
    case replacement
    case appShutdown
}

public enum DismissalDecision: Equatable, Sendable {
    case began(DismissalCause)
    case alreadyDismissing(DismissalCause)
    case staleSession
}

public enum PresentationCancellationReason: String, Equatable, Sendable {
    case replacement
    case globalDisable
    case sourceShutdown
    case permissionLoss
    case recovery
    case queueRemoval
    case appShutdown
    case finished
}

public enum PresentationValidation: Equatable, Sendable {
    case valid
    case staleSession
    case wrongNotification
    case wrongPhase
    case staleContentRevision
    case dismissing
}

public struct PresentationSessionSnapshot: Equatable, Sendable {
    public let id: PresentationSessionID
    public let contentRevision: UInt64
    public let phase: PresentationPhase
    public let remainingTransientDuration: Duration?
    public let timerDeadline: PresentationInstant?
    public let isPaused: Bool
    public let dismissalCause: DismissalCause?
    public let cancellationReason: PresentationCancellationReason?
    public let pendingExternalUpdateID: UUID?
    public let hasPendingExternalDisappearance: Bool
}
