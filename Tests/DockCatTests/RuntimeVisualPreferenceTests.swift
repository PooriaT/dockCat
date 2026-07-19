import AppKit
import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class RuntimeVisualPreferenceTests: XCTestCase {
    func testScaleFacingAndBreathingUseIndependentNodes() async {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        scene.applyVisualPreferences(policy(scale: 2, idle: false), completeActiveAnimations: false)

        XCTAssertEqual(scene.userScaleForTesting, 2)
        XCTAssertFalse(scene.isBreathingForTesting)

        let left = CatAnimationContext(
            dockEdge: .bottom, direction: .left, purpose: .presentation,
            phase: .turning, facing: .left, isCarryingMiniCard: false,
            reducedMotion: false
        )
        let leftResult = await scene.runAsync(
            .turnToPresentation(left), duration: 20,
            preferences: policy(mode: .animationsPaused, scale: 2, idle: false)
        )
        XCTAssertEqual(leftResult, .completed)
        XCTAssertEqual(scene.userScaleForTesting, 2)
        XCTAssertEqual(scene.facingScaleForTesting, -1)

        let up = CatAnimationContext(
            dockEdge: .left, direction: .up, purpose: .presentation,
            phase: .turning, facing: .up, isCarryingMiniCard: false,
            reducedMotion: false
        )
        _ = await scene.runAsync(
            .turnToPresentation(up), duration: 20,
            preferences: policy(mode: .animationsPaused, scale: 2, idle: false)
        )
        XCTAssertEqual(scene.userScaleForTesting, 2)
        XCTAssertEqual(scene.facingRotationForTesting, .pi / 2, accuracy: 0.000_001)
    }

    func testIdleToggleStartsOneKeyedLoopAndStopsWithoutChangingScale() {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        scene.applyVisualPreferences(policy(scale: 1.5, idle: false), completeActiveAnimations: false)
        XCTAssertFalse(scene.isBreathingForTesting)
        XCTAssertEqual(scene.userScaleForTesting, 1.5)

        let enabled = policy(scale: 1.5, idle: true)
        scene.applyVisualPreferences(enabled, completeActiveAnimations: false)
        scene.applyVisualPreferences(enabled, completeActiveAnimations: false)
        XCTAssertTrue(scene.isBreathingForTesting)
        XCTAssertEqual(scene.userScaleForTesting, 1.5)
    }

    func testIdleToggleDoesNotCompleteActiveChoreographyAndAppliesAtNextSleep() async {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        let operation = Task {
            await scene.runAsync(.wake, duration: 30, preferences: .default)
        }
        await Task.yield()

        scene.applyVisualPreferences(
            policy(idle: false), completeActiveAnimations: false
        )
        operation.cancel()
        let result = await operation.value

        XCTAssertEqual(result, .cancelled)
        scene.resetToSleeping()
        XCTAssertFalse(scene.isBreathingForTesting)
    }

    func testPauseVisualsCompletesActiveSpriteWaiterAtFinalState() async {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        let operation = Task {
            await scene.runAsync(.wake, duration: 30, preferences: .default)
        }
        await Task.yield()

        scene.applyVisualPreferences(
            policy(mode: .animationsPaused), completeActiveAnimations: true
        )

        let result = await operation.value
        XCTAssertEqual(result, .completed)
        XCTAssertFalse(scene.isBreathingForTesting)
    }

    func testScaleResizePreservesGlobalAnchor() {
        let controller = CatWindowController()
        let placement = makePlacement(
            sleeping: CGPoint(x: -420, y: 85),
            presentation: CGPoint(x: -120, y: 85)
        )
        _ = controller.updatePlacement(placement, logicalState: .home, sessionID: nil)

        XCTAssertTrue(controller.applyVisualPreferences(policy(scale: 2)))

        let geometry = CatOverlayGeometry(scale: 2)
        XCTAssertEqual(
            controller.panelOriginForTesting,
            CGPoint(geometry.panelOrigin(
                preservingGlobalVisualAnchor: Point(x: -420, y: 85)
            ))
        )
        XCTAssertEqual(controller.panelSizeForTesting, CGSize(geometry.panelSize))
        XCTAssertEqual(controller.sceneScaleForTesting, 2)
    }

    func testWalkingDisabledRelocatesWithoutStartingWalkLoop() async {
        let controller = CatWindowController()
        let placement = makePlacement(
            sleeping: CGPoint(x: 200, y: 80),
            presentation: CGPoint(x: 360, y: 80)
        )
        _ = controller.updatePlacement(placement, logicalState: .home, sessionID: nil)
        let notificationID = UUID()
        let result = await controller.animate(
            .walkToPresentation,
            preferences: policy(mode: .walkingDisabled),
            sessionID: .init(generation: 1, notificationID: notificationID)
        )

        XCTAssertEqual(result, .completed)
        XCTAssertFalse(controller.sceneIsWalkingForTesting)
        XCTAssertEqual(
            controller.panelOriginForTesting,
            CGPoint(CatOverlayGeometry(scale: 1).panelOrigin(
                preservingGlobalVisualAnchor: Point(x: 360, y: 80)
            ))
        )
    }

    func testPauseVisualsCompletesActiveCardPresentationAtStableFrame() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(
            sourceName: "test", title: "", message: ""
        )
        let sessionID = PresentationSessionID(
            generation: 1, notificationID: notification.id
        )
        _ = controller.updatePlacementContext(
            CardPlacementContext(
                presentationAnchor: CGPoint(x: 400, y: 100),
                dockEdge: .bottom,
                visibleScreenFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876),
                catExclusionFrame: nil,
                offset: 14,
                placementRevision: 1
            ),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )
        let operation = Task {
            await controller.present(
                notification: notification,
                preferences: DockCatPreferences(),
                from: .zero,
                visualPreferences: .default,
                sessionID: sessionID
            )
        }
        await Task.yield()

        controller.applyVisualPreferences(policy(mode: .animationsPaused))

        let result = await operation.value
        XCTAssertEqual(result, .completed)
        XCTAssertTrue(controller.panelIsVisibleForTesting)
        XCTAssertEqual(controller.panelFrameForTesting, controller.stableCardFrameForTesting)
        controller.forceHide()
    }

    private func makePlacement(
        sleeping: CGPoint,
        presentation: CGPoint
    ) -> DockPlacement {
        .init(
            sleepingPoint: sleeping,
            presentationPoint: presentation,
            baseSleepingPoint: sleeping,
            basePresentationPoint: presentation,
            edge: .bottom,
            geometryConfidence: .observedVisibleFrameInset,
            screenFrame: CGRect(x: -1_440, y: 0, width: 1_440, height: 900),
            visibleScreenFrame: CGRect(x: -1_440, y: 24, width: 1_440, height: 876),
            displayIdentity: .init(value: "runtime-test", quality: .stableUUID),
            displayName: "Runtime Test",
            requestedDisplayAvailable: true,
            usedDisplayFallback: false,
            migratedSelection: nil
        )
    }
}

private func policy(
    mode: VisualAnimationMode = .full,
    speed: Double = 1,
    scale: Double = 1,
    idle: Bool = true
) -> EffectiveAnimationPreferences {
    EffectiveAnimationPreferences(inputs: .init(
        appReducedMotion: mode == .reducedMotion,
        systemReducedMotion: false,
        disableWalking: mode == .walkingDisabled,
        pauseAnimations: mode == .animationsPaused,
        idleAnimation: idle,
        animationSpeed: speed,
        catScale: scale
    ))
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
