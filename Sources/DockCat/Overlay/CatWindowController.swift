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
    private var isMotionPaused = false
    private lazy var motionDriver = CatMotionDriver(updater: panel)

    private enum AnchorOffset {
        static let x: CGFloat = 75
        static let y: CGFloat = 35
    }

    private static func panelOrigin(forVisualAnchor anchor: CGPoint) -> CGPoint {
        CGPoint(x: anchor.x - AnchorOffset.x, y: anchor.y - AnchorOffset.y)
    }

    private func targetOrigin(for animation: CatAnimation) -> CGPoint? {
        switch animation {
        case .walkToPresentation:
            Self.panelOrigin(forVisualAnchor: presentationPoint)
        case .walkHome:
            Self.panelOrigin(forVisualAnchor: sleepingPoint)
        default:
            nil
        }
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
        if let targetOrigin = targetOrigin(for: animation) {
            let plan = CatMotionPlanner.plan(from: CatMotionPoint(panel.frame.origin), requestedDestination: CatMotionPoint(targetOrigin), dockEdge: dockEdge, speed: speed, reducedMotion: reducedMotion)
            async let sceneResult: Void = scene.runAsync(animation, duration: plan.duration, reducedMotion: reducedMotion)
            async let motionResult = motionDriver.move(to: targetOrigin, dockEdge: dockEdge, speed: speed, reducedMotion: reducedMotion)
            let (_, result) = await (sceneResult, motionResult)
            await finishWalkIfNeeded(animation, after: result, speed: speed, reducedMotion: reducedMotion)
        } else {
            await scene.runAsync(animation, duration: CatMotionTiming.minimumDuration / max(CatMotionTiming.minimumSpeed, min(speed, CatMotionTiming.maximumSpeed)), reducedMotion: reducedMotion)
        }
    }

    private func finishWalkIfNeeded(_ animation: CatAnimation, after result: CatMotionCompletion, speed: Double, reducedMotion: Bool) async {
        var result = result
        while result == .cancelled, !Task.isCancelled {
            while isMotionPaused, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            guard !Task.isCancelled, let currentTargetOrigin = targetOrigin(for: animation) else { return }
            result = await motionDriver.move(to: currentTargetOrigin, dockEdge: dockEdge, speed: speed, reducedMotion: reducedMotion)
        }
    }
    func pause() { isMotionPaused = true; motionDriver.cancelActiveMotion(); scene.isPaused = true }
    func resume() { isMotionPaused = false; scene.isPaused = false }
}
