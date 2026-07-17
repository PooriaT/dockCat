public enum CatEffectExecutionOutcome: Equatable, Sendable {
    case completed(nextEvent: CatEvent?)
    case cancelled
    case failed
}

public enum CatEffectChainAction: Equatable, Sendable {
    case submit(CatEvent)
    case stop
    case recover
}

/// Pure policy shared by the coordinator and its tests. A rejected decision exposes no
/// effect, and an effect failure can request recovery but never a later event.
public enum CatEffectChainPolicy {
    public static func effect(for result: CatTransitionResult) -> CatCoordinatorEffect? {
        result.transition?.effect
    }

    public static func action(after outcome: CatEffectExecutionOutcome) -> CatEffectChainAction {
        switch outcome {
        case .completed(.some(let event)): .submit(event)
        case .completed(.none), .cancelled: .stop
        case .failed: .recover
        }
    }
}

/// Idempotence gate for fail-closed recovery. The coordinator resets it only after the
/// safe sleeping state and visuals have been restored.
public struct CatRecoveryGate: Sendable {
    private var recoveryInProgress = false

    public init() {}

    public mutating func requestRecovery() -> Bool {
        guard !recoveryInProgress else { return false }
        recoveryInProgress = true
        return true
    }

    public mutating func recoveryCompleted() {
        recoveryInProgress = false
    }
}
