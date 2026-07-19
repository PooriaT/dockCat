import Foundation

public enum DockCatRuntimeMode: String, Equatable, Sendable, CaseIterable {
    case enabling
    case running
    case deliveryPaused
    case disabling
    case disabled
    case shuttingDown

    public var isEnabled: Bool {
        switch self {
        case .enabling, .running, .deliveryPaused: true
        case .disabling, .disabled, .shuttingDown: false
        }
    }

    public var acceptsSubmissions: Bool { self == .running || self == .deliveryPaused }
    public var permitsQueueClaims: Bool { self == .running }
    public var acceptsPauseMutation: Bool { self == .running || self == .deliveryPaused }
    public var isTransitioning: Bool { self == .enabling || self == .disabling }
}

public struct DockCatRuntimeSnapshot: Equatable, Sendable {
    public let mode: DockCatRuntimeMode
    public let visualMode: VisualAnimationMode
    public let systemSourceRequested: Bool

    public init(
        mode: DockCatRuntimeMode,
        visualMode: VisualAnimationMode,
        systemSourceRequested: Bool
    ) {
        self.mode = mode
        self.visualMode = visualMode
        self.systemSourceRequested = systemSourceRequested
    }

    public var systemSourceRuntimeAllowed: Bool {
        systemSourceRequested && mode.acceptsSubmissions
    }
}

public enum DockCatRuntimeAction: Equatable, Sendable {
    case beginEnabling
    case finishEnabling
    case pauseDelivery
    case resumeDelivery
    case beginDisabling
    case finishDisabling
    case updateVisualMode(VisualAnimationMode)
    case updateSystemSourceRequested(Bool)
    case shutdown
}

public enum DockCatRuntimeTransitionReason: String, Equatable, Sendable {
    case userEnabled
    case enableCompleted
    case deliveryPaused
    case deliveryResumed
    case userDisabled
    case disableCompleted
    case visualPreferenceChanged
    case systemSourcePreferenceChanged
    case applicationShutdown
}

public struct DockCatRuntimeTransition: Equatable, Sendable {
    public let previous: DockCatRuntimeSnapshot
    public let next: DockCatRuntimeSnapshot
    public let action: DockCatRuntimeAction
    public let reason: DockCatRuntimeTransitionReason

    public init(
        previous: DockCatRuntimeSnapshot,
        next: DockCatRuntimeSnapshot,
        action: DockCatRuntimeAction,
        reason: DockCatRuntimeTransitionReason
    ) {
        self.previous = previous
        self.next = next
        self.action = action
        self.reason = reason
    }
}

public enum DockCatRuntimeTransitionRejectionReason: String, Equatable, Sendable {
    case invalidTransition
    case shutdownIsTerminal
    case alreadyInRequestedState
}

public struct DockCatRuntimeTransitionRejection: Equatable, Sendable {
    public let snapshot: DockCatRuntimeSnapshot
    public let action: DockCatRuntimeAction
    public let reason: DockCatRuntimeTransitionRejectionReason
}

public enum DockCatRuntimeTransitionResult: Equatable, Sendable {
    case accepted(DockCatRuntimeTransition)
    case rejected(DockCatRuntimeTransitionRejection)

    public var transition: DockCatRuntimeTransition? {
        guard case .accepted(let transition) = self else { return nil }
        return transition
    }
}

/// Foundation-only transition authority. Side effects belong to the application coordinator.
public struct DockCatRuntimeLifecycle: Equatable, Sendable {
    public private(set) var snapshot: DockCatRuntimeSnapshot

    public init(
        initiallyEnabled: Bool,
        visualMode: VisualAnimationMode,
        systemSourceRequested: Bool
    ) {
        snapshot = .init(
            mode: initiallyEnabled ? .enabling : .disabled,
            visualMode: visualMode,
            systemSourceRequested: systemSourceRequested
        )
    }

    @discardableResult
    public mutating func apply(_ action: DockCatRuntimeAction) -> DockCatRuntimeTransitionResult {
        let previous = snapshot
        if previous.mode == .shuttingDown {
            return reject(action, reason: .shutdownIsTerminal)
        }

        let mode: DockCatRuntimeMode
        let visualMode: VisualAnimationMode
        let sourceRequested: Bool
        let reason: DockCatRuntimeTransitionReason

        switch action {
        case .shutdown:
            mode = .shuttingDown
            visualMode = previous.visualMode
            sourceRequested = previous.systemSourceRequested
            reason = .applicationShutdown
        case .beginEnabling where previous.mode == .disabled:
            mode = .enabling
            visualMode = previous.visualMode
            sourceRequested = previous.systemSourceRequested
            reason = .userEnabled
        case .finishEnabling where previous.mode == .enabling:
            mode = .running
            visualMode = previous.visualMode
            sourceRequested = previous.systemSourceRequested
            reason = .enableCompleted
        case .pauseDelivery where previous.mode == .running:
            mode = .deliveryPaused
            visualMode = previous.visualMode
            sourceRequested = previous.systemSourceRequested
            reason = .deliveryPaused
        case .resumeDelivery where previous.mode == .deliveryPaused:
            mode = .running
            visualMode = previous.visualMode
            sourceRequested = previous.systemSourceRequested
            reason = .deliveryResumed
        case .beginDisabling where previous.mode == .running || previous.mode == .deliveryPaused || previous.mode == .enabling:
            mode = .disabling
            visualMode = previous.visualMode
            sourceRequested = previous.systemSourceRequested
            reason = .userDisabled
        case .finishDisabling where previous.mode == .disabling:
            mode = .disabled
            visualMode = previous.visualMode
            sourceRequested = previous.systemSourceRequested
            reason = .disableCompleted
        case .updateVisualMode(let newMode):
            guard newMode != previous.visualMode else {
                return reject(action, reason: .alreadyInRequestedState)
            }
            mode = previous.mode
            visualMode = newMode
            sourceRequested = previous.systemSourceRequested
            reason = .visualPreferenceChanged
        case .updateSystemSourceRequested(let requested):
            guard requested != previous.systemSourceRequested else {
                return reject(action, reason: .alreadyInRequestedState)
            }
            mode = previous.mode
            visualMode = previous.visualMode
            sourceRequested = requested
            reason = .systemSourcePreferenceChanged
        default:
            return reject(action, reason: .invalidTransition)
        }

        snapshot = .init(
            mode: mode,
            visualMode: visualMode,
            systemSourceRequested: sourceRequested
        )
        return .accepted(.init(previous: previous, next: snapshot, action: action, reason: reason))
    }

    private func reject(
        _ action: DockCatRuntimeAction,
        reason: DockCatRuntimeTransitionRejectionReason
    ) -> DockCatRuntimeTransitionResult {
        .rejected(.init(snapshot: snapshot, action: action, reason: reason))
    }
}
