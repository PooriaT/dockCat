import Foundation

public enum CatMotionAxis: Equatable, Sendable {
    case horizontal
    case vertical

    public init(dockEdge: DockEdge) {
        switch dockEdge {
        case .bottom:
            self = .horizontal
        case .left, .right:
            self = .vertical
        }
    }
}

public enum CatMotionCompletion: Equatable, Sendable {
    case completed
    case cancelled
}

public struct CatMotionPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CatMotionTiming: Equatable, Sendable {
    public static let defaultPointsPerSecond = 520.0
    public static let minimumSpeed = 0.25
    public static let maximumSpeed = 4.0
    public static let minimumDuration = 0.18
    public static let maximumDuration = 1.8
    public static let reducedMotionDuration = 0.12

    public var pointsPerSecond: Double
    public var minimumSpeed: Double
    public var maximumSpeed: Double
    public var minimumDuration: TimeInterval
    public var maximumDuration: TimeInterval
    public var reducedMotionDuration: TimeInterval

    public init(
        pointsPerSecond: Double = Self.defaultPointsPerSecond,
        minimumSpeed: Double = Self.minimumSpeed,
        maximumSpeed: Double = Self.maximumSpeed,
        minimumDuration: TimeInterval = Self.minimumDuration,
        maximumDuration: TimeInterval = Self.maximumDuration,
        reducedMotionDuration: TimeInterval = Self.reducedMotionDuration
    ) {
        self.pointsPerSecond = pointsPerSecond
        self.minimumSpeed = minimumSpeed
        self.maximumSpeed = maximumSpeed
        self.minimumDuration = minimumDuration
        self.maximumDuration = maximumDuration
        self.reducedMotionDuration = reducedMotionDuration
    }

    public func clampedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return 1 }
        return min(max(speed, minimumSpeed), maximumSpeed)
    }
}

public struct CatMotionPlan: Equatable, Sendable {
    public let axis: CatMotionAxis
    public let start: CatMotionPoint
    public let destination: CatMotionPoint
    public let distance: Double
    public let duration: TimeInterval
    public let usesReducedMotion: Bool

    public func point(at progress: Double) -> CatMotionPoint {
        let t = min(max(progress.isFinite ? progress : 0, 0), 1)
        return CatMotionPoint(
            x: start.x + (destination.x - start.x) * t,
            y: start.y + (destination.y - start.y) * t
        )
    }
}

public enum CatMotionPlanner {
    public static func plan(
        from start: CatMotionPoint,
        requestedDestination: CatMotionPoint,
        dockEdge: DockEdge,
        speed: Double,
        reducedMotion: Bool,
        timing: CatMotionTiming = .init()
    ) -> CatMotionPlan {
        let axis = CatMotionAxis(dockEdge: dockEdge)
        let destination: CatMotionPoint
        let distance: Double
        switch axis {
        case .horizontal:
            destination = CatMotionPoint(x: requestedDestination.x, y: start.y)
            distance = abs(Double(destination.x - start.x))
        case .vertical:
            destination = CatMotionPoint(x: start.x, y: requestedDestination.y)
            distance = abs(Double(destination.y - start.y))
        }

        let duration: TimeInterval
        if reducedMotion {
            duration = timing.reducedMotionDuration
        } else {
            let velocity = max(1, timing.pointsPerSecond * timing.clampedSpeed(speed))
            duration = min(max(distance / velocity, timing.minimumDuration), timing.maximumDuration)
        }

        return CatMotionPlan(axis: axis, start: start, destination: destination, distance: distance, duration: duration, usesReducedMotion: reducedMotion)
    }
}

public struct CatMotionSessionCoordinator: Sendable {
    public private(set) var activeSessionID = 0
    public private(set) var cancelledSessionIDs: Set<Int> = []

    public init() {}

    @discardableResult
    public mutating func startReplacementSession() -> Int {
        if activeSessionID != 0 { cancelledSessionIDs.insert(activeSessionID) }
        activeSessionID += 1
        return activeSessionID
    }

    public mutating func cancelActiveSession() {
        guard activeSessionID != 0 else { return }
        cancelledSessionIDs.insert(activeSessionID)
    }

    public mutating func cancel(sessionID: Int) {
        cancelledSessionIDs.insert(sessionID)
    }

    public func canUpdate(sessionID: Int) -> Bool {
        sessionID == activeSessionID && !cancelledSessionIDs.contains(sessionID)
    }

    public mutating func complete(sessionID: Int) -> CatMotionCompletion {
        guard canUpdate(sessionID: sessionID) else { return .cancelled }
        return .completed
    }
}
