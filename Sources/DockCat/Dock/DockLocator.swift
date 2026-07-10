import AppKit
import DockCatCore

struct DockPlacement {
    let sleepingPoint: CGPoint
    let presentationPoint: CGPoint
    let edge: DockEdge
}

@MainActor
final class DockLocator {
    func locate(preferences: DockCatPreferences) -> DockPlacement {
        let screen: NSScreen?
        if preferences.displaySelection == "main" {
            screen = NSScreen.main ?? NSScreen.screens.first
        } else if preferences.displaySelection == "automatic" {
            screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
        } else {
            screen = NSScreen.screens.first(where: { Self.identifier(for: $0) == preferences.displaySelection }) ?? NSScreen.main ?? NSScreen.screens.first
        }
        guard let screen else { return .init(sleepingPoint: .zero, presentationPoint: .zero, edge: .bottom) }
        let frame = screen.frame, visible = screen.visibleFrame
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
                edge: .bottom
            )
        case .left:
            let halfEstimatedDockHeight = min(frame.height * 0.31, max(240, CGFloat(inferred.thickness) * 4.8))
            return .init(sleepingPoint: CGPoint(x: frame.minX + inset, y: frame.midY + (start ? halfEstimatedDockHeight : -halfEstimatedDockHeight) + preferences.dockEndOffset), presentationPoint: CGPoint(x: frame.minX + inset, y: frame.midY), edge: .left)
        case .right:
            let halfEstimatedDockHeight = min(frame.height * 0.31, max(240, CGFloat(inferred.thickness) * 4.8))
            return .init(sleepingPoint: CGPoint(x: frame.maxX - inset, y: frame.midY + (start ? halfEstimatedDockHeight : -halfEstimatedDockHeight) + preferences.dockEndOffset), presentationPoint: CGPoint(x: frame.maxX - inset, y: frame.midY), edge: .right)
        }
    }
    static func identifier(for screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }
}
