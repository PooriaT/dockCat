import AppKit
import SpriteKit
import DockCatCore

private extension CatMotionPoint {
    init(_ point: CGPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
}

@MainActor
final class CatWindowController {
    private let panel = CatOverlayPanel()
    private let scene = CatScene(size: CGSize(width: 150, height: 110))
    private var sleepingPoint = CGPoint.zero
    private var presentationPoint = CGPoint.zero
    private var dockEdge: DockEdge = .bottom
    private lazy var motionDriver = CatMotionDriver(updater: panel)

    private enum AnchorOffset {
        static let x: CGFloat = 75
        static let y: CGFloat = 35
    }

    private static func panelOrigin(forVisualAnchor anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x - AnchorOffset.x, y: anchor.y - AnchorOffset.y)
    }

    init() {
        let view = SKView(frame: panel.contentView?.bounds ?? .zero)
        view.allowsTransparency = true; view.presentScene(scene); panel.contentView = view
    }
    func position(at sleeping: CGPoint, presentationPoint: CGPoint, dockEdge: DockEdge) {
        self.sleepingPoint = sleeping
        self.presentationPoint = presentationPoint
        self.dockEdge = dockEdge
        motionDriver.cancelActiveMotion()
        panel.setFrameOrigin(Self.panelOrigin(forVisualAnchor: sleeping))
    }
    func showSleeping() { panel.orderFrontRegardless(); scene.playLoop() }
    func animate(_ animation: CatAnimation, speed: Double, reducedMotion: Bool) async {
        let target = animation == .walkToPresentation ? presentationPoint : (animation == .walkHome ? sleepingPoint : nil)
        if let target {
            let targetOrigin = Self.panelOrigin(forVisualAnchor: target)
            let plan = CatMotionPlanner.plan(from: CatMotionPoint(panel.frame.origin), requestedDestination: CatMotionPoint(targetOrigin), dockEdge: dockEdge, speed: speed, reducedMotion: reducedMotion)
            async let sceneResult: Void = scene.runAsync(animation, duration: plan.duration, reducedMotion: reducedMotion)
            async let motionResult = motionDriver.move(to: targetOrigin, dockEdge: dockEdge, speed: speed, reducedMotion: reducedMotion)
            _ = await (sceneResult, motionResult)
        } else {
            await scene.runAsync(animation, duration: CatMotionTiming.minimumDuration / max(CatMotionTiming.minimumSpeed, min(speed, CatMotionTiming.maximumSpeed)), reducedMotion: reducedMotion)
        }
    }
    func pause() { motionDriver.cancelActiveMotion(); scene.isPaused = true }
    func resume() { scene.isPaused = false }
}
