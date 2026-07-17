import AppKit
import DockCatCore

struct DockPlacement {
    let sleepingPoint: CGPoint
    let presentationPoint: CGPoint
    let baseSleepingPoint: CGPoint
    let basePresentationPoint: CGPoint
    let edge: DockEdge
    let geometryConfidence: DockGeometryConfidence
    let screenFrame: CGRect
    let visibleScreenFrame: CGRect
    let displayIdentity: DisplayIdentity
    let displayName: String
    let requestedDisplayAvailable: Bool
    let usedDisplayFallback: Bool
    let migratedSelection: DisplaySelection?
}

@MainActor
final class DockLocator {
    func locate(
        preferences: DockCatPreferences,
        catalog: DisplayCatalog,
        safeToRestoreSpecific: Bool
    ) -> DockPlacement? {
        guard case .resolved(let resolution) = catalog.resolve(
            selection: preferences.displaySelection,
            safeToRestoreSpecific: safeToRestoreSpecific
        ) else { return nil }

        let descriptor = resolution.descriptor
        let inferred = DockGeometryInference.infer(
            frame: descriptor.frame, visible: descriptor.visibleFrame
        )
        let calibration = preferences.calibration(
            for: descriptor.identity, edge: inferred.edge
        )
        let planned = DockPlacementPlanner.plan(
            frame: descriptor.frame,
            geometry: inferred,
            sleepingCorner: preferences.sleepingCorner,
            positionOffset: preferences.positionOffset,
            dockEndOffset: preferences.dockEndOffset,
            calibration: calibration
        )
        return .init(
            sleepingPoint: CGPoint(x: planned.sleepingPoint.x, y: planned.sleepingPoint.y),
            presentationPoint: CGPoint(x: planned.presentationPoint.x, y: planned.presentationPoint.y),
            baseSleepingPoint: CGPoint(x: planned.baseSleepingPoint.x, y: planned.baseSleepingPoint.y),
            basePresentationPoint: CGPoint(x: planned.basePresentationPoint.x, y: planned.basePresentationPoint.y),
            edge: inferred.edge,
            geometryConfidence: inferred.confidence,
            screenFrame: CGRect(
                x: descriptor.frame.x, y: descriptor.frame.y,
                width: descriptor.frame.width, height: descriptor.frame.height
            ),
            visibleScreenFrame: CGRect(
                x: descriptor.visibleFrame.x, y: descriptor.visibleFrame.y,
                width: descriptor.visibleFrame.width, height: descriptor.visibleFrame.height
            ),
            displayIdentity: descriptor.identity,
            displayName: descriptor.localizedName,
            requestedDisplayAvailable: resolution.requestedDisplayAvailable,
            usedDisplayFallback: resolution.usedFallback,
            migratedSelection: resolution.migratedSelection
        )
    }
}
