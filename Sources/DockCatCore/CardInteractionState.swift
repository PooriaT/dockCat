import Foundation

public enum CardInteractionTrigger: String, Equatable, Sendable {
    case pointer
    case keyboardNavigation
    case accessibility
}

public enum CardInteractionExit: String, Equatable, Sendable {
    case close
    case openAction
    case sourceDismissal
    case replacement
    case queueAdvancement
    case globalDisable
    case permissionLoss
    case failClosedRecovery
    case appShutdown

    public var restorationPolicy: CardFocusRestorationPolicy {
        self == .openAction ? .never : .restoreIfSafe
    }
}

public enum CardFocusRestorationPolicy: Equatable, Sendable {
    case restoreIfSafe
    case never
}

/// A privacy-safe reference to an application that may regain focus. AppKit objects and
/// application metadata deliberately remain outside DockCatCore.
public struct CardApplicationIdentity: Equatable, Sendable {
    public let processIdentifier: Int32

    public init(processIdentifier: Int32) {
        self.processIdentifier = processIdentifier
    }
}

public struct CardInteractionSession: Equatable, Sendable {
    public let generation: UInt64
    public let presentationSessionID: PresentationSessionID
    public let previousApplication: CardApplicationIdentity?
    public let trigger: CardInteractionTrigger
    public let dockCatBecameActive: Bool

    public init(
        generation: UInt64,
        presentationSessionID: PresentationSessionID,
        previousApplication: CardApplicationIdentity?,
        trigger: CardInteractionTrigger,
        dockCatBecameActive: Bool
    ) {
        self.generation = generation
        self.presentationSessionID = presentationSessionID
        self.previousApplication = previousApplication
        self.trigger = trigger
        self.dockCatBecameActive = dockCatBecameActive
    }
}

public enum CardInteractionMode: Equatable, Sendable {
    case passive
    case interactive(CardInteractionSession)
}

public enum CardInteractionRequestResult: Equatable, Sendable {
    case entered(CardInteractionSession)
    case unchanged(CardInteractionSession)
    case stalePresentation
}

public struct CardInteractionExitDecision: Equatable, Sendable {
    public let exit: CardInteractionExit
    public let session: CardInteractionSession
    public let restorationPolicy: CardFocusRestorationPolicy

    public init(exit: CardInteractionExit, session: CardInteractionSession) {
        self.exit = exit
        self.session = session
        restorationPolicy = exit.restorationPolicy
    }
}

public enum CardInteractionExitResult: Equatable, Sendable {
    case exited(CardInteractionExitDecision)
    case noInteraction
    case stalePresentation
    case staleGeneration
}

/// Deterministic interaction state for the one visible presentation session. Presenting or
/// replacing content is always passive; only an explicit request increments the generation.
public struct CardInteractionState: Equatable, Sendable {
    public private(set) var mode: CardInteractionMode = .passive
    public private(set) var presentationSessionID: PresentationSessionID?
    public private(set) var latestInteractionGeneration: UInt64 = 0

    public init() {}

    public mutating func beginPresentation(_ sessionID: PresentationSessionID) {
        presentationSessionID = sessionID
        mode = .passive
    }

    public mutating func requestInteraction(
        for sessionID: PresentationSessionID,
        trigger: CardInteractionTrigger,
        previousApplication: CardApplicationIdentity?,
        dockCatBecameActive: Bool
    ) -> CardInteractionRequestResult {
        guard presentationSessionID == sessionID else { return .stalePresentation }
        if case .interactive(let existing) = mode {
            return .unchanged(existing)
        }

        latestInteractionGeneration &+= 1
        let session = CardInteractionSession(
            generation: latestInteractionGeneration,
            presentationSessionID: sessionID,
            previousApplication: previousApplication,
            trigger: trigger,
            dockCatBecameActive: dockCatBecameActive
        )
        mode = .interactive(session)
        return .entered(session)
    }

    public mutating func exit(
        _ exit: CardInteractionExit,
        for sessionID: PresentationSessionID,
        expectedInteractionGeneration: UInt64? = nil
    ) -> CardInteractionExitResult {
        guard presentationSessionID == sessionID else { return .stalePresentation }
        guard case .interactive(let session) = mode else { return .noInteraction }
        if let expectedInteractionGeneration,
           expectedInteractionGeneration != session.generation {
            return .staleGeneration
        }
        mode = .passive
        return .exited(.init(exit: exit, session: session))
    }

    @discardableResult
    public mutating func recordDockCatActivation(
        for sessionID: PresentationSessionID,
        interactionGeneration: UInt64,
        becameActive: Bool
    ) -> Bool {
        guard case .interactive(let session) = mode,
              session.presentationSessionID == sessionID,
              session.generation == interactionGeneration else { return false }
        mode = .interactive(.init(
            generation: session.generation,
            presentationSessionID: session.presentationSessionID,
            previousApplication: session.previousApplication,
            trigger: session.trigger,
            dockCatBecameActive: becameActive
        ))
        return true
    }

    public mutating func clearPresentation(_ sessionID: PresentationSessionID) {
        guard presentationSessionID == sessionID else { return }
        presentationSessionID = nil
        mode = .passive
    }

    public func isCurrent(
        interactionGeneration: UInt64,
        presentationSessionID: PresentationSessionID
    ) -> Bool {
        latestInteractionGeneration == interactionGeneration
            && self.presentationSessionID == presentationSessionID
    }
}

public enum CardInitialFocusTarget: String, Equatable, Sendable {
    case open
    case close
    case message

    public static func resolve(
        hasOpenAction: Bool,
        canDismiss: Bool,
        bodySupportsKeyboardScrolling: Bool
    ) -> CardInitialFocusTarget? {
        if hasOpenAction { return .open }
        if canDismiss { return .close }
        if bodySupportsKeyboardScrolling { return .message }
        return nil
    }
}
