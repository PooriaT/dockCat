import Foundation

public enum CatTravelDirection: Equatable, Sendable {
    case left, right, up, down, stationary

    public var reversed: Self {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        case .stationary: .stationary
        }
    }
}

public enum CatTravelPurpose: Equatable, Sendable { case presentation, home }

public enum CatFacing: Equatable, Sendable { case left, right, up, down, resting }

public enum CatLocomotionPhase: Equatable, Sendable {
    case sleeping
    case waking
    case turning
    case pickingUp
    case walking
    case staticCarry
    case stopping
    case waiting
    case settling
    case settled
    case cancelled

    public var showsMiniCard: Bool {
        switch self {
        case .pickingUp, .walking, .staticCarry, .stopping, .waiting, .cancelled:
            true
        case .sleeping, .waking, .turning, .settling, .settled:
            false
        }
    }

    public var isWalkingLoop: Bool { self == .walking }
}

public struct CatAnimationContext: Equatable, Sendable {
    public let dockEdge: DockEdge
    public let direction: CatTravelDirection
    public let purpose: CatTravelPurpose
    public let phase: CatLocomotionPhase
    public let facing: CatFacing
    public let isCarryingMiniCard: Bool
    public let reducedMotion: Bool

    public init(
        dockEdge: DockEdge,
        direction: CatTravelDirection,
        purpose: CatTravelPurpose,
        phase: CatLocomotionPhase,
        facing: CatFacing,
        isCarryingMiniCard: Bool,
        reducedMotion: Bool
    ) {
        self.dockEdge = dockEdge
        self.direction = direction
        self.purpose = purpose
        self.phase = phase
        self.facing = facing
        self.isCarryingMiniCard = isCarryingMiniCard
        self.reducedMotion = reducedMotion
    }
}

public enum CatLocomotionResolver {
    public static let nearZeroTolerance = 0.5

    public static func direction(from start: CatMotionPoint, to end: CatMotionPoint, tolerance: Double = nearZeroTolerance) -> CatTravelDirection {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dx) >= abs(dy), abs(dx) > tolerance { return dx > 0 ? .right : .left }
        if abs(dy) > tolerance { return dy > 0 ? .up : .down }
        return .stationary
    }

    public static func facing(for direction: CatTravelDirection, dockEdge: DockEdge) -> CatFacing {
        switch direction {
        case .left: .left
        case .right: .right
        case .up: .up
        case .down: .down
        case .stationary:
            switch dockEdge {
            case .bottom: .right
            case .left, .right: .up
            }
        }
    }

    public static func travelContext(
        from start: CatMotionPoint,
        to end: CatMotionPoint,
        dockEdge: DockEdge,
        purpose: CatTravelPurpose,
        phase: CatLocomotionPhase,
        reducedMotion: Bool
    ) -> CatAnimationContext {
        let resolvedDirection = direction(from: start, to: end)
        let selectedPhase = reducedMotion && phase == .walking ? CatLocomotionPhase.staticCarry : phase
        return CatAnimationContext(
            dockEdge: dockEdge,
            direction: resolvedDirection,
            purpose: purpose,
            phase: selectedPhase,
            facing: facing(for: resolvedDirection, dockEdge: dockEdge),
            isCarryingMiniCard: selectedPhase.showsMiniCard,
            reducedMotion: reducedMotion
        )
    }

    public static func homeContext(from outbound: CatAnimationContext, phase: CatLocomotionPhase) -> CatAnimationContext {
        let direction = outbound.direction.reversed
        return CatAnimationContext(
            dockEdge: outbound.dockEdge,
            direction: direction,
            purpose: .home,
            phase: outbound.reducedMotion && phase == .walking ? .staticCarry : phase,
            facing: facing(for: direction, dockEdge: outbound.dockEdge),
            isCarryingMiniCard: (outbound.reducedMotion && phase == .walking ? CatLocomotionPhase.staticCarry : phase).showsMiniCard,
            reducedMotion: outbound.reducedMotion
        )
    }

    public static func phase(after completion: CatMotionCompletion) -> CatLocomotionPhase {
        completion == .completed ? .stopping : .cancelled
    }
}
