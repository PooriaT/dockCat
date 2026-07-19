import AppKit
import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class PresentationAnimationCancellationTests: XCTestCase {
    func testCancelledSpriteActionResolvesItsWaiter() async {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        let task = Task {
            await scene.runAsync(.wake, duration: 30, preferences: .default)
        }
        await Task.yield()
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    func testReplacingSpriteActionCancelsOldWaiter() async {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        let old = Task {
            await scene.runAsync(.wake, duration: 30, preferences: .default)
        }
        await Task.yield()
        let replacement = Task {
            await scene.runAsync(.wake, duration: 30, preferences: .default)
        }

        let oldResult = await old.value
        XCTAssertEqual(oldResult, .cancelled)
        replacement.cancel()
        let replacementResult = await replacement.value
        XCTAssertEqual(replacementResult, .cancelled)
    }

    func testCancelledCardPresentationResolvesPromptly() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(sourceName: "test", title: "", message: "")
        let sessionID = PresentationSessionID(generation: 1, notificationID: notification.id)
        let task = Task {
            await controller.present(
                notification: notification,
                preferences: DockCatPreferences(),
                from: .zero,
                reducedMotion: false,
                sessionID: sessionID
            )
        }
        await Task.yield()
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    func testForceHideResolvesActiveCardOperation() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(sourceName: "test", title: "", message: "")
        let sessionID = PresentationSessionID(generation: 1, notificationID: notification.id)
        let task = Task {
            await controller.present(
                notification: notification,
                preferences: DockCatPreferences(),
                from: .zero,
                reducedMotion: false,
                sessionID: sessionID
            )
        }
        await Task.yield()
        controller.forceHide()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    func testCancelledTravelCannotSnapToDestination() async {
        let panel = MotionPanelFake(origin: .zero)
        let driver = CatMotionDriver(updater: panel)
        let presentationID = PresentationSessionID(generation: 1, notificationID: UUID())
        let destination = CGPoint(x: 10_000, y: 0)
        let task = Task {
            await driver.move(
                to: destination,
                dockEdge: .bottom,
                preferences: policy(speed: 0.25),
                presentationSessionID: presentationID
            )
        }
        await Task.yield()
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
        XCTAssertNotEqual(panel.frameOrigin, destination)
    }

    func testReplacementMotionRejectsOldFinalSnap() async {
        let panel = MotionPanelFake(origin: .zero)
        let driver = CatMotionDriver(updater: panel)
        let presentationID = PresentationSessionID(generation: 1, notificationID: UUID())
        let oldDestination = CGPoint(x: 10_000, y: 0)
        let old = Task {
            await driver.move(
                to: oldDestination, dockEdge: .bottom,
                preferences: policy(speed: 0.25),
                presentationSessionID: presentationID
            )
        }
        await Task.yield()
        let newDestination = CGPoint(x: 120, y: 0)
        let replacement = Task {
            await driver.move(
                to: newDestination, dockEdge: .bottom,
                preferences: policy(speed: 4),
                presentationSessionID: presentationID
            )
        }

        let oldResult = await old.value
        let replacementResult = await replacement.value
        XCTAssertEqual(oldResult, .cancelled)
        XCTAssertEqual(replacementResult, .completed)
        XCTAssertEqual(panel.frameOrigin, newDestination)
        XCTAssertNotEqual(panel.frameOrigin, oldDestination)
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

@MainActor
private final class MotionPanelFake: CatPanelFrameUpdating {
    var frameOrigin: CGPoint
    var alphaValue: CGFloat = 1

    init(origin: CGPoint) { frameOrigin = origin }
    func setFrameOrigin(_ point: CGPoint) { frameOrigin = point }
}
