import AppKit
import SpriteKit
import DockCatCore
import OSLog

private extension CatMotionPoint {
    init(_ point: CGPoint) { self.init(x: Double(point.x), y: Double(point.y)) }
}

private extension Point {
    init(_ point: CGPoint) { self.init(x: point.x, y: point.y) }
}

private extension CGPoint {
    init(_ point: Point) { self.init(x: point.x, y: point.y) }
}

private extension CGSize {
    init(_ size: Size) { self.init(width: size.width, height: size.height) }
}

private extension CGRect {
    init(_ rect: Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

struct CatPlacementUpdateOutcome {
    let previousDockEdge: DockEdge
    let motionWasRetargeted: Bool
}

@MainActor
final class CatWindowController {
    private let panel = CatOverlayPanel()
    private let scene = CatScene(size: CGSize(width: 150, height: 110))
    private var overlayGeometry = CatOverlayGeometry(scale: 1)
    private var visualPreferences: EffectiveAnimationPreferences = .default
    private var sleepingPoint = CGPoint.zero
    private var presentationPoint = CGPoint.zero
    private var dockEdge: DockEdge = .bottom
    private var placementRevision: UInt64 = 0
    private var visualWorkGeneration: UInt64 = 0
    private var isMotionPaused = false
    private var motionResumeWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    private lazy var motionDriver = CatMotionDriver(updater: panel)
    private let logger = Logger(
        subsystem: "com.example.DockCat", category: "CatVisualPreferences"
    )

    private func panelOrigin(forVisualAnchor anchor: CGPoint) -> CGPoint {
        CGPoint(overlayGeometry.panelOrigin(preservingGlobalVisualAnchor: Point(anchor)))
    }

    private func targetOrigin(for animation: CatAnimation) -> CGPoint? {
        switch animation {
        case .walkToPresentation, .walkToPresentationLoop:
            panelOrigin(forVisualAnchor: presentationPoint)
        case .walkHome, .walkHomeLoop:
            panelOrigin(forVisualAnchor: sleepingPoint)
        default:
            nil
        }
    }

    init() {
        let view = SKView(frame: panel.contentView?.bounds ?? .zero)
        view.allowsTransparency = true; view.presentScene(scene); panel.contentView = view
        scene.updateLayout(
            size: CGSize(overlayGeometry.panelSize),
            visualAnchor: CGPoint(overlayGeometry.visualAnchorInPanel),
            preferences: visualPreferences
        )
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
            panel.setFrameOrigin(panelOrigin(forVisualAnchor: sleepingPoint))
            motionWasRetargeted = false
        case .retargetPresentationTravel, .retargetHomeTravel:
            // Cancelling the motion operation wakes the existing travel loop. The loop
            // retains its presentation session and replans from the panel's actual origin.
            motionDriver.cancelActiveMotion()
            motionWasRetargeted = sessionID != nil
        case .moveToPresentation:
            motionDriver.cancelActiveMotion()
            panel.setFrameOrigin(panelOrigin(forVisualAnchor: presentationPoint))
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

    /// Applies scale and behavior without changing logical placement or presentation identity.
    /// The live global anchor is recovered from the old geometry before the panel is resized.
    @discardableResult
    func applyVisualPreferences(
        _ preferences: EffectiveAnimationPreferences
    ) -> Bool {
        let oldPreferences = visualPreferences
        let oldGeometry = overlayGeometry
        let liveAnchor = oldGeometry.globalVisualAnchor(
            forPanelOrigin: Point(panel.frame.origin)
        )
        visualPreferences = preferences
        overlayGeometry = CatOverlayGeometry(scale: preferences.catScale)
        let newOrigin = overlayGeometry.panelOrigin(
            preservingGlobalVisualAnchor: liveAnchor
        )
        panel.setFrame(
            CGRect(origin: CGPoint(newOrigin), size: CGSize(overlayGeometry.panelSize)),
            display: true
        )
        scene.updateLayout(
            size: CGSize(overlayGeometry.panelSize),
            visualAnchor: CGPoint(overlayGeometry.visualAnchorInPanel),
            preferences: preferences
        )

        let behaviorChanged = oldPreferences.mode != preferences.mode
            || oldPreferences.speed != preferences.speed
        let geometryChanged = oldGeometry != overlayGeometry
        scene.applyVisualPreferences(
            preferences,
            completeActiveAnimations: behaviorChanged
        )
        if behaviorChanged || geometryChanged {
            motionDriver.cancelActiveMotion()
        }
        return geometryChanged
    }

    func animate(
        _ animation: CatAnimation,
        preferences: EffectiveAnimationPreferences,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        visualPreferences = preferences
        if targetOrigin(for: animation) != nil {
            return await animateTravel(
                animation, sessionID: sessionID
            )
        } else {
            return await scene.runAsync(
                animation,
                duration: CatMotionTiming.minimumDuration / max(
                    CatMotionTiming.minimumSpeed,
                    min(preferences.speed, CatMotionTiming.maximumSpeed)
                ),
                preferences: preferences
            )
        }
    }

    private func animateTravel(
        _ animation: CatAnimation,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        let purpose: CatTravelPurpose = switch animation { case .walkHome: .home; default: .presentation }
        let ownedVisualWorkGeneration = visualWorkGeneration
        guard let initialTargetOrigin = targetOrigin(for: animation) else { return .cancelled }
        let initialEdge = dockEdge
        let initialPlan = CatMotionPlanner.plan(
            from: CatMotionPoint(panel.frame.origin),
            requestedDestination: CatMotionPoint(initialTargetOrigin), dockEdge: initialEdge,
            speed: visualPreferences.speed,
            reducedMotion: visualPreferences.mode != .full
        )
        let initialPreferences = visualPreferences
        let skipsWalking = initialPreferences.mode == .walkingDisabled
            || initialPreferences.mode == .animationsPaused
        let turn = CatLocomotionResolver.travelContext(
            from: initialPlan.start, to: initialPlan.destination, dockEdge: initialEdge,
            purpose: purpose, phase: .turning,
            reducedMotion: initialPreferences.mode == .reducedMotion
        )
        if !skipsWalking {
            guard await scene.runAsync(
                purpose == .home ? .turnHome(turn) : .turnToPresentation(turn),
                duration: 0.18, preferences: initialPreferences
            ) == .completed, !Task.isCancelled,
                  ownedVisualWorkGeneration == visualWorkGeneration else { return .cancelled }
        } else if purpose == .presentation {
            scene.showCarriedMiniCard()
        }

        while !Task.isCancelled, ownedVisualWorkGeneration == visualWorkGeneration {
            guard await waitForMotionResume(),
                  !Task.isCancelled,
                  ownedVisualWorkGeneration == visualWorkGeneration,
                  let currentTargetOrigin = targetOrigin(for: animation) else {
                return .cancelled
            }
            let revision = placementRevision
            let currentEdge = dockEdge
            let currentPreferences = visualPreferences
            if currentPreferences.mode == .walkingDisabled {
                logger.info("Cat travel usedNoWalkingRelocation=true")
            }
            let plan = CatMotionPlanner.plan(
                from: CatMotionPoint(panel.frame.origin),
                requestedDestination: CatMotionPoint(currentTargetOrigin),
                dockEdge: currentEdge, speed: currentPreferences.speed,
                reducedMotion: currentPreferences.mode != .full
            )
            let walk = CatLocomotionResolver.travelContext(
                from: plan.start, to: plan.destination, dockEdge: currentEdge,
                purpose: purpose, phase: .walking,
                reducedMotion: currentPreferences.mode != .full
            )
            if currentPreferences.mode == .full
                || currentPreferences.mode == .reducedMotion {
                guard await scene.runAsync(
                    purpose == .home ? .walkHomeLoop(walk) : .walkToPresentationLoop(walk),
                    duration: plan.duration, preferences: currentPreferences
                ) == .completed, !Task.isCancelled,
                      ownedVisualWorkGeneration == visualWorkGeneration else { return .cancelled }
            } else {
                scene.stopLocomotion(cancelled: true, context: walk)
                if purpose == .presentation { scene.showCarriedMiniCard() }
            }
            guard revision == placementRevision else { continue }

            let result = await motionDriver.move(
                to: currentTargetOrigin, dockEdge: currentEdge,
                preferences: currentPreferences,
                presentationSessionID: sessionID
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
                    purpose: purpose, phase: .stopping,
                    reducedMotion: currentPreferences.mode == .reducedMotion
                )
                let stopResult = await scene.runAsync(
                    .stopAtPresentation(stop), duration: 0.15,
                    preferences: currentPreferences
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

    /// The live handoff location follows the panel during travel and is the correct target
    /// for rebasing an in-progress dismissal animation.
    func handoffSourceRect() -> CGRect {
        let origin = panel.frame.origin
        let currentVisualAnchor = overlayGeometry.globalVisualAnchor(
            forPanelOrigin: Point(origin)
        )
        return CGRect(overlayGeometry.handoffFrame(
            forGlobalVisualAnchor: currentVisualAnchor,
            facing: scene.facingForGeometry
        ))
    }

    /// Card planning protects the destination handoff location even while the panel is still
    /// travelling from an older screen or Dock edge.
    func presentationExclusionFrame() -> CGRect {
        CGRect(overlayGeometry.presentationExclusionFrame(
            forGlobalVisualAnchor: Point(presentationPoint)
        ))
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
        panel.setFrameOrigin(panelOrigin(forVisualAnchor: sleepingPoint))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    var panelOriginForTesting: CGPoint { panel.frame.origin }
    var panelSizeForTesting: CGSize { panel.frame.size }
    var sceneScaleForTesting: CGFloat { scene.userScaleForTesting }
    var sceneIsWalkingForTesting: Bool { scene.isWalkingForTesting }

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
