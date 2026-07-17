import AppKit
import SpriteKit
import DockCatCore

private extension CatMotionPoint {
    init(_ point: CGPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
}

struct CatPlacementUpdateOutcome {
    let previousDockEdge: DockEdge
    let motionWasRetargeted: Bool
}

@MainActor
final class CatWindowController {
    private let panel = CatOverlayPanel()
    private let scene = CatScene(size: CGSize(width: 150, height: 110))
    private var sleepingPoint = CGPoint.zero
    private var presentationPoint = CGPoint.zero
    private var dockEdge: DockEdge = .bottom
    private var placementRevision: UInt64 = 0
    private var visualWorkGeneration: UInt64 = 0
    private var isMotionPaused = false
    private var motionResumeWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
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
        case .walkToPresentation, .walkToPresentationLoop:
            Self.panelOrigin(forVisualAnchor: presentationPoint)
        case .walkHome, .walkHomeLoop:
            Self.panelOrigin(forVisualAnchor: sleepingPoint)
        default:
            nil
        }
    }

    init() {
        let view = SKView(frame: panel.contentView?.bounds ?? .zero)
        view.allowsTransparency = true; view.presentScene(scene); panel.contentView = view
    }
    /// Installs anchors first, then applies the response selected from authoritative
    /// choreography state. Anchor updates never imply a recovery reset.
    func updatePlacement(
        _ placement: DockPlacement,
        logicalState: CatLogicalPlacement,
        sessionID: PresentationSessionID?
    ) -> CatPlacementUpdateOutcome {
        let previousDockEdge = dockEdge
        sleepingPoint = placement.sleepingPoint
        presentationPoint = placement.presentationPoint
        dockEdge = placement.edge
        placementRevision &+= 1

        let action = PlacementRefreshPolicy.action(for: logicalState)
        let motionWasRetargeted: Bool
        switch action {
        case .moveToHome:
            panel.setFrameOrigin(Self.panelOrigin(forVisualAnchor: sleepingPoint))
            motionWasRetargeted = false
        case .retargetPresentationTravel, .retargetHomeTravel:
            // Cancelling the motion operation wakes the existing travel loop. The loop
            // retains its presentation session and replans from the panel's actual origin.
            motionDriver.cancelActiveMotion()
            motionWasRetargeted = sessionID != nil
        case .moveToPresentation:
            motionDriver.cancelActiveMotion()
            panel.setFrameOrigin(Self.panelOrigin(forVisualAnchor: presentationPoint))
            motionWasRetargeted = false
        case .preserveRecoveryVisuals:
            motionWasRetargeted = false
        }
        return .init(
            previousDockEdge: previousDockEdge,
            motionWasRetargeted: motionWasRetargeted
        )
    }
    func showSleeping() { panel.orderFrontRegardless(); scene.playLoop() }
    func animate(
        _ animation: CatAnimation,
        speed: Double,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        if targetOrigin(for: animation) != nil {
            return await animateTravel(
                animation, speed: speed, reducedMotion: reducedMotion,
                sessionID: sessionID
            )
        } else {
            return await scene.runAsync(
                animation,
                duration: CatMotionTiming.minimumDuration / max(
                    CatMotionTiming.minimumSpeed, min(speed, CatMotionTiming.maximumSpeed)
                ),
                reducedMotion: reducedMotion
            )
        }
    }

    private func animateTravel(
        _ animation: CatAnimation,
        speed: Double,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        let purpose: CatTravelPurpose = switch animation { case .walkHome: .home; default: .presentation }
        let ownedVisualWorkGeneration = visualWorkGeneration
        guard let initialTargetOrigin = targetOrigin(for: animation) else { return .cancelled }
        let initialEdge = dockEdge
        let initialPlan = CatMotionPlanner.plan(
            from: CatMotionPoint(panel.frame.origin),
            requestedDestination: CatMotionPoint(initialTargetOrigin), dockEdge: initialEdge,
            speed: speed, reducedMotion: reducedMotion
        )
        let turn = CatLocomotionResolver.travelContext(
            from: initialPlan.start, to: initialPlan.destination, dockEdge: initialEdge,
            purpose: purpose, phase: .turning, reducedMotion: reducedMotion
        )
        guard await scene.runAsync(
            purpose == .home ? .turnHome(turn) : .turnToPresentation(turn),
            duration: 0.18, reducedMotion: reducedMotion
        ) == .completed, !Task.isCancelled,
              ownedVisualWorkGeneration == visualWorkGeneration else { return .cancelled }

        while !Task.isCancelled, ownedVisualWorkGeneration == visualWorkGeneration {
            guard await waitForMotionResume(),
                  !Task.isCancelled,
                  ownedVisualWorkGeneration == visualWorkGeneration,
                  let currentTargetOrigin = targetOrigin(for: animation) else {
                return .cancelled
            }
            let revision = placementRevision
            let currentEdge = dockEdge
            let plan = CatMotionPlanner.plan(
                from: CatMotionPoint(panel.frame.origin),
                requestedDestination: CatMotionPoint(currentTargetOrigin),
                dockEdge: currentEdge, speed: speed, reducedMotion: reducedMotion
            )
            let walk = CatLocomotionResolver.travelContext(
                from: plan.start, to: plan.destination, dockEdge: currentEdge,
                purpose: purpose, phase: .walking, reducedMotion: reducedMotion
            )
            guard await scene.runAsync(
                purpose == .home ? .walkHomeLoop(walk) : .walkToPresentationLoop(walk),
                duration: plan.duration, reducedMotion: reducedMotion
            ) == .completed, !Task.isCancelled,
                  ownedVisualWorkGeneration == visualWorkGeneration else { return .cancelled }
            guard revision == placementRevision else { continue }

            let result = await motionDriver.move(
                to: currentTargetOrigin, dockEdge: currentEdge, speed: speed,
                reducedMotion: reducedMotion, presentationSessionID: sessionID
            )
            guard !Task.isCancelled,
                  ownedVisualWorkGeneration == visualWorkGeneration else { return .cancelled }
            if result == .cancelled || revision != placementRevision {
                scene.stopLocomotion(cancelled: true, context: walk)
                continue
            }

            scene.stopLocomotion(cancelled: false, context: walk)
            if purpose == .presentation {
                let stop = CatLocomotionResolver.travelContext(
                    from: plan.start, to: plan.destination, dockEdge: currentEdge,
                    purpose: purpose, phase: .stopping, reducedMotion: reducedMotion
                )
                let stopResult = await scene.runAsync(
                    .stopAtPresentation(stop), duration: 0.15, reducedMotion: reducedMotion
                )
                guard stopResult == .completed, !Task.isCancelled,
                      ownedVisualWorkGeneration == visualWorkGeneration else {
                    return .cancelled
                }
                // A refresh can land after panel travel completes but while the stopping
                // pose is active. Re-plan instead of accepting that now-stale arrival.
                if revision != placementRevision { continue }
                return .completed
            }
            return .completed
        }
        return .cancelled
    }

    func showCarriedCard() { scene.showCarriedMiniCard() }
    func hideCarriedCard() { scene.hideCarriedMiniCard() }
    func prepareHandoffPose() { scene.prepareHandoffPose() }
    func completeHandoffPose() { scene.completeHandoffPose() }

    func handoffSourceRect() -> CGRect {
        let origin = panel.frame.origin
        let center = CGPoint(x: origin.x + AnchorOffset.x + 42, y: origin.y + AnchorOffset.y + 38)
        return CGRect(x: center.x - 18, y: center.y - 12, width: 36, height: 24)
    }
    func pause() { isMotionPaused = true; motionDriver.cancelActiveMotion(); scene.isPaused = true }
    func resume() {
        isMotionPaused = false
        scene.isPaused = false
        resolveMotionResumeWaiters(resumed: true)
    }
    func cancelVisualWork() {
        visualWorkGeneration &+= 1
        isMotionPaused = false
        scene.isPaused = false
        resolveMotionResumeWaiters(resumed: false)
        motionDriver.cancelActiveMotion()
        scene.cancelAnimations()
    }
    func resetToSleeping() {
        cancelVisualWork()
        scene.resetToSleeping()
        panel.setFrameOrigin(Self.panelOrigin(forVisualAnchor: sleepingPoint))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    var panelOriginForTesting: CGPoint { panel.frame.origin }

    private func waitForMotionResume() async -> Bool {
        guard isMotionPaused else { return !Task.isCancelled }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            guard !Task.isCancelled else { return false }
            return await withCheckedContinuation { continuation in
                if isMotionPaused {
                    motionResumeWaiters[waiterID] = continuation
                } else {
                    continuation.resume(returning: true)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.motionResumeWaiters.removeValue(forKey: waiterID)?.resume(returning: false)
            }
        }
    }

    private func resolveMotionResumeWaiters(resumed: Bool) {
        let waiters = Array(motionResumeWaiters.values)
        motionResumeWaiters.removeAll()
        waiters.forEach { $0.resume(returning: resumed) }
    }
}
