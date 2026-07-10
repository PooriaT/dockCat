import AppKit
import SpriteKit

@MainActor
final class CatWindowController {
    private let panel = CatOverlayPanel()
    private let scene = CatScene(size: CGSize(width: 150, height: 110))
    private var sleepingPoint = CGPoint.zero
    private var presentationPoint = CGPoint.zero

    init() {
        let view = SKView(frame: panel.contentView?.bounds ?? .zero)
        view.allowsTransparency = true; view.presentScene(scene); panel.contentView = view
    }
    func position(at sleeping: CGPoint, presentationPoint: CGPoint) {
        self.sleepingPoint = sleeping; self.presentationPoint = presentationPoint
        panel.setFrameOrigin(CGPoint(x: sleeping.x - 75, y: sleeping.y - 35))
    }
    func showSleeping() { panel.orderFrontRegardless(); scene.playLoop() }
    func animate(_ animation: CatAnimation, speed: Double, reducedMotion: Bool) async {
        let target = animation == .walkToPresentation ? presentationPoint : (animation == .walkHome ? sleepingPoint : nil)
        let duration = max(0.1, 0.65 / max(0.25, speed))
        await withCheckedContinuation { continuation in
            scene.run(animation, duration: duration, reducedMotion: reducedMotion) { [weak self] in
                if let target { self?.panel.setFrameOrigin(CGPoint(x: target.x - 75, y: target.y - 35)) }
                continuation.resume()
            }
        }
    }
    func pause() { scene.isPaused = true }
    func resume() { scene.isPaused = false }
}
