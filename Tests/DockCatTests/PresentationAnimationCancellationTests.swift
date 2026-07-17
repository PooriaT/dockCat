import AppKit
import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class PresentationAnimationCancellationTests: XCTestCase {
    func testCancelledSpriteActionResolvesItsWaiter() async {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        let task = Task {
            await scene.runAsync(.wake, duration: 30, reducedMotion: false)
        }
        await Task.yield()
        task.cancel()

        let result = await task.value
        XCTAssertEqual(result, .cancelled)
    }

    func testReplacingSpriteActionCancelsOldWaiter() async {
        let scene = CatScene(size: CGSize(width: 150, height: 110))
        let old = Task {
            await scene.runAsync(.wake, duration: 30, reducedMotion: false)
        }
        await Task.yield()
        let replacement = Task {
            await scene.runAsync(.wake, duration: 30, reducedMotion: false)
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
                speed: 0.25,
                reducedMotion: false,
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
                to: oldDestination, dockEdge: .bottom, speed: 0.25,
                reducedMotion: false, presentationSessionID: presentationID
            )
        }
        await Task.yield()
        let newDestination = CGPoint(x: 120, y: 0)
        let replacement = Task {
            await driver.move(
                to: newDestination, dockEdge: .bottom, speed: 4,
                reducedMotion: false, presentationSessionID: presentationID
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

@MainActor
private final class MotionPanelFake: CatPanelFrameUpdating {
    var frameOrigin: CGPoint
    var alphaValue: CGFloat = 1

    init(origin: CGPoint) { frameOrigin = origin }
    func setFrameOrigin(_ point: CGPoint) { frameOrigin = point }
}
