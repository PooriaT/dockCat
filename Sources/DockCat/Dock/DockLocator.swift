import AppKit
import DockCatCore

struct DockPlacement {
    let sleepingPoint: CGPoint
    let presentationPoint: CGPoint
    let edge: DockEdge
    let screenFrame: CGRect
    let visibleScreenFrame: CGRect
    let displayIdentifier: String
    let usedDisplayFallback: Bool
}

@MainActor
final class DockLocator {
    func locate(preferences: DockCatPreferences) -> DockPlacement? {
        let screen: NSScreen?
        let usedDisplayFallback: Bool
        if preferences.displaySelection == "main" {
            screen = NSScreen.main ?? NSScreen.screens.first
            usedDisplayFallback = NSScreen.main == nil && screen != nil
        } else if preferences.displaySelection == "automatic" {
            let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            screen = mouseScreen ?? NSScreen.main ?? NSScreen.screens.first
            usedDisplayFallback = mouseScreen == nil && screen != nil
        } else {
            let selectedScreen = NSScreen.screens.first(where: { Self.identifier(for: $0) == preferences.displaySelection })
            screen = selectedScreen ?? NSScreen.main ?? NSScreen.screens.first
            usedDisplayFallback = selectedScreen == nil && screen != nil
        }
        // A temporary lack of screens is not valid geometry. AppState retains the last
        // valid placement and visible overlay frames until a later refresh resolves one.
        guard let screen else { return nil }
        let frame = screen.frame, visible = screen.visibleFrame
        let displayIdentifier = Self.identifier(for: screen)
        let inferred = DockGeometryInference.infer(frame: .init(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height), visible: .init(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height))
        let inset = CGFloat(inferred.thickness) + preferences.positionOffset
        let start = preferences.sleepingCorner == .start
        switch inferred.edge {
        case .bottom:
            // Public APIs expose the Dock edge and thickness, but not individual
            // item frames. Estimate its visual ends around screen centre instead
            // of using the screen corners. The end side is where Trash lives.
            let halfEstimatedDockWidth = min(frame.width * 0.31, max(260, CGFloat(inferred.thickness) * 5.2))
            return .init(
                sleepingPoint: CGPoint(x: frame.midX + (start ? -halfEstimatedDockWidth : halfEstimatedDockWidth) + preferences.dockEndOffset, y: frame.minY + inset),
                presentationPoint: CGPoint(x: frame.midX, y: frame.minY + inset),
                edge: .bottom,
                screenFrame: frame,
                visibleScreenFrame: visible,
                displayIdentifier: displayIdentifier,
                usedDisplayFallback: usedDisplayFallback
            )
        case .left:
            let halfEstimatedDockHeight = min(frame.height * 0.31, max(240, CGFloat(inferred.thickness) * 4.8))
            return .init(sleepingPoint: CGPoint(x: frame.minX + inset, y: frame.midY + (start ? halfEstimatedDockHeight : -halfEstimatedDockHeight) + preferences.dockEndOffset), presentationPoint: CGPoint(x: frame.minX + inset, y: frame.midY), edge: .left, screenFrame: frame, visibleScreenFrame: visible, displayIdentifier: displayIdentifier, usedDisplayFallback: usedDisplayFallback)
        case .right:
            let halfEstimatedDockHeight = min(frame.height * 0.31, max(240, CGFloat(inferred.thickness) * 4.8))
            return .init(sleepingPoint: CGPoint(x: frame.maxX - inset, y: frame.midY + (start ? halfEstimatedDockHeight : -halfEstimatedDockHeight) + preferences.dockEndOffset), presentationPoint: CGPoint(x: frame.maxX - inset, y: frame.midY), edge: .right, screenFrame: frame, visibleScreenFrame: visible, displayIdentifier: displayIdentifier, usedDisplayFallback: usedDisplayFallback)
        }
    }
    static func identifier(for screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }
}
