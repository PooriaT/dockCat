import AppKit
import DockCatCore

private extension CatMotionPoint {
    init(_ point: CGPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
}

private extension CGPoint {
    init(_ point: CatMotionPoint) { self.init(x: point.x, y: point.y) }
}

@MainActor
protocol CatPanelFrameUpdating: AnyObject {
    var frameOrigin: CGPoint { get }
    var alphaValue: CGFloat { get set }
    func setFrameOrigin(_ point: CGPoint)
}

extension NSPanel: CatPanelFrameUpdating {
    var frameOrigin: CGPoint { frame.origin }
}

@MainActor
final class CatMotionDriver {
    private weak var updater: CatPanelFrameUpdating?
    private var coordinator = CatMotionSessionCoordinator()

    init(updater: CatPanelFrameUpdating) {
        self.updater = updater
    }

    func cancelActiveMotion() {
        coordinator.cancelActiveSession()
    }

    func move(to targetOrigin: CGPoint, dockEdge: DockEdge, speed: Double, reducedMotion: Bool) async -> CatMotionCompletion {
        guard let updater else { return .cancelled }
        let sessionID = coordinator.startReplacementSession()
        let plan = CatMotionPlanner.plan(
            from: CatMotionPoint(updater.frameOrigin),
            requestedDestination: CatMotionPoint(targetOrigin),
            dockEdge: dockEdge,
            speed: speed,
            reducedMotion: reducedMotion
        )

        if reducedMotion {
            return await runReducedMotion(plan, sessionID: sessionID, updater: updater)
        }
        return await runTravel(plan, sessionID: sessionID, updater: updater)
    }

    private func runReducedMotion(_ plan: CatMotionPlan, sessionID: Int, updater: CatPanelFrameUpdating) async -> CatMotionCompletion {
        let originalAlpha = updater.alphaValue
        updater.alphaValue = max(0.35, originalAlpha * 0.55)
        do { try await Task.sleep(nanoseconds: UInt64(plan.duration * 1_000_000_000)) } catch { coordinator.cancel(sessionID: sessionID) }
        guard !Task.isCancelled, coordinator.canUpdate(sessionID: sessionID) else {
            updater.alphaValue = originalAlpha
            return .cancelled
        }
        updater.setFrameOrigin(CGPoint(plan.destination))
        updater.alphaValue = originalAlpha
        return coordinator.complete(sessionID: sessionID)
    }

    private func runTravel(_ plan: CatMotionPlan, sessionID: Int, updater: CatPanelFrameUpdating) async -> CatMotionCompletion {
        let clock = ContinuousClock()
        let startInstant = clock.now
        while true {
            guard !Task.isCancelled, coordinator.canUpdate(sessionID: sessionID) else { return .cancelled }
            let elapsed = startInstant.duration(to: clock.now)
            let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            if elapsedSeconds >= plan.duration { break }
            let progress = elapsedSeconds / plan.duration
            updater.setFrameOrigin(CGPoint(plan.point(at: progress)))
            do { try await Task.sleep(nanoseconds: 8_000_000) } catch { coordinator.cancel(sessionID: sessionID); return .cancelled }
        }

        guard !Task.isCancelled, coordinator.canUpdate(sessionID: sessionID) else { return .cancelled }
        updater.setFrameOrigin(CGPoint(plan.destination))
        return coordinator.complete(sessionID: sessionID)
    }
}
