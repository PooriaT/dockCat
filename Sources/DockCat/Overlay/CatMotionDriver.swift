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
    private var presentationSessionByMotionID: [Int: PresentationSessionID] = [:]

    init(updater: CatPanelFrameUpdating) {
        self.updater = updater
    }

    func cancelActiveMotion() {
        coordinator.cancelActiveSession()
    }

    func move(
        to targetOrigin: CGPoint,
        dockEdge: DockEdge,
        speed: Double,
        reducedMotion: Bool,
        presentationSessionID: PresentationSessionID
    ) async -> CatMotionCompletion {
        guard let updater else { return .cancelled }
        let motionID = coordinator.startReplacementSession()
        presentationSessionByMotionID = [motionID: presentationSessionID]
        let plan = CatMotionPlanner.plan(
            from: CatMotionPoint(updater.frameOrigin),
            requestedDestination: CatMotionPoint(targetOrigin),
            dockEdge: dockEdge,
            speed: speed,
            reducedMotion: reducedMotion
        )

        if reducedMotion {
            return await runReducedMotion(
                plan, motionID: motionID, presentationSessionID: presentationSessionID,
                updater: updater
            )
        }
        return await runTravel(
            plan, motionID: motionID, presentationSessionID: presentationSessionID,
            updater: updater
        )
    }

    private func runReducedMotion(
        _ plan: CatMotionPlan,
        motionID: Int,
        presentationSessionID: PresentationSessionID,
        updater: CatPanelFrameUpdating
    ) async -> CatMotionCompletion {
        let originalAlpha = updater.alphaValue
        updater.alphaValue = max(0.35, originalAlpha * 0.55)
        do { try await Task.sleep(nanoseconds: UInt64(plan.duration * 1_000_000_000)) }
        catch { coordinator.cancel(sessionID: motionID) }
        guard canUpdate(motionID: motionID, presentationSessionID: presentationSessionID) else {
            updater.alphaValue = originalAlpha
            return .cancelled
        }
        updater.setFrameOrigin(CGPoint(plan.destination))
        updater.alphaValue = originalAlpha
        return coordinator.complete(sessionID: motionID)
    }

    private func runTravel(
        _ plan: CatMotionPlan,
        motionID: Int,
        presentationSessionID: PresentationSessionID,
        updater: CatPanelFrameUpdating
    ) async -> CatMotionCompletion {
        let clock = ContinuousClock()
        let startInstant = clock.now
        while true {
            guard canUpdate(motionID: motionID, presentationSessionID: presentationSessionID) else {
                return .cancelled
            }
            let elapsed = startInstant.duration(to: clock.now)
            let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            if elapsedSeconds >= plan.duration { break }
            let progress = elapsedSeconds / plan.duration
            updater.setFrameOrigin(CGPoint(plan.point(at: progress)))
            do { try await Task.sleep(nanoseconds: 8_000_000) }
            catch { coordinator.cancel(sessionID: motionID); return .cancelled }
        }

        guard canUpdate(motionID: motionID, presentationSessionID: presentationSessionID) else {
            return .cancelled
        }
        updater.setFrameOrigin(CGPoint(plan.destination))
        return coordinator.complete(sessionID: motionID)
    }

    private func canUpdate(
        motionID: Int,
        presentationSessionID: PresentationSessionID
    ) -> Bool {
        !Task.isCancelled && coordinator.canUpdate(sessionID: motionID)
            && presentationSessionByMotionID[motionID] == presentationSessionID
    }
}
