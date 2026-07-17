import Foundation

public struct PlannedDockPlacement: Equatable, Sendable {
    public var baseSleepingPoint: Point
    public var basePresentationPoint: Point
    public var sleepingPoint: Point
    public var presentationPoint: Point

    public init(
        baseSleepingPoint: Point,
        basePresentationPoint: Point,
        sleepingPoint: Point,
        presentationPoint: Point
    ) {
        self.baseSleepingPoint = baseSleepingPoint
        self.basePresentationPoint = basePresentationPoint
        self.sleepingPoint = sleepingPoint
        self.presentationPoint = presentationPoint
    }
}

public enum DockPlacementPlanner {
    public static func plan(
        frame: Rect,
        geometry: InferredDockGeometry,
        sleepingCorner: DockCatPreferences.SleepingCorner,
        positionOffset: Double,
        dockEndOffset: Double,
        calibration: DockCalibration
    ) -> PlannedDockPlacement {
        let inset = geometry.thickness + positionOffset
        let start = sleepingCorner == .start
        let home: Point
        let presentation: Point
        switch geometry.edge {
        case .bottom:
            let halfDock = min(frame.width * 0.31, max(260, geometry.thickness * 5.2))
            home = .init(
                x: frame.midX + (start ? -halfDock : halfDock) + dockEndOffset,
                y: frame.minY + inset
            )
            presentation = .init(x: frame.midX, y: frame.minY + inset)
        case .left:
            let halfDock = min(frame.height * 0.31, max(240, geometry.thickness * 4.8))
            home = .init(
                x: frame.minX + inset,
                y: frame.midY + (start ? halfDock : -halfDock) + dockEndOffset
            )
            presentation = .init(x: frame.minX + inset, y: frame.midY)
        case .right:
            let halfDock = min(frame.height * 0.31, max(240, geometry.thickness * 4.8))
            home = .init(
                x: frame.maxX - inset,
                y: frame.midY + (start ? halfDock : -halfDock) + dockEndOffset
            )
            presentation = .init(x: frame.maxX - inset, y: frame.midY)
        }
        return .init(
            baseSleepingPoint: home,
            basePresentationPoint: presentation,
            sleepingPoint: apply(calibration.home, to: home, edge: geometry.edge),
            presentationPoint: apply(calibration.presentation, to: presentation, edge: geometry.edge)
        )
    }

    public static func apply(_ calibration: DockAnchorCalibration, to point: Point, edge: DockEdge) -> Point {
        switch edge {
        case .bottom:
            .init(x: point.x + calibration.alongDock, y: point.y + calibration.awayFromDock)
        case .left:
            .init(x: point.x + calibration.awayFromDock, y: point.y + calibration.alongDock)
        case .right:
            .init(x: point.x - calibration.awayFromDock, y: point.y + calibration.alongDock)
        }
    }
}
