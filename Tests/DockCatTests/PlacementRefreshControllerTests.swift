import AppKit
import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class PlacementRefreshControllerTests: XCTestCase {
    func testHomeRefreshMovesToSleepingOrigin() {
        let controller = CatWindowController()
        let placement = makePlacement(sleeping: CGPoint(x: 240, y: 180), presentation: CGPoint(x: 500, y: 180))

        _ = controller.updatePlacement(placement, logicalState: .home, sessionID: nil)

        XCTAssertEqual(controller.panelOriginForTesting, CGPoint(x: 165, y: 145))
    }

    func testPresentationRefreshMovesToPresentationOrigin() {
        let controller = CatWindowController()
        let placement = makePlacement(sleeping: CGPoint(x: 240, y: 180), presentation: CGPoint(x: 500, y: 180))

        _ = controller.updatePlacement(placement, logicalState: .presentation, sessionID: nil)

        XCTAssertEqual(controller.panelOriginForTesting, CGPoint(x: 425, y: 145))
    }

    func testOutboundAndHomeRetargetsPreserveCurrentOrigin() {
        let controller = CatWindowController()
        let initial = makePlacement(sleeping: CGPoint(x: 240, y: 180), presentation: CGPoint(x: 500, y: 180))
        _ = controller.updatePlacement(initial, logicalState: .home, sessionID: nil)
        let origin = controller.panelOriginForTesting
        let sessionID = PresentationSessionID(generation: 1, notificationID: UUID())
        let changed = makePlacement(sleeping: CGPoint(x: 320, y: 240), presentation: CGPoint(x: 710, y: 240), edge: .left)

        let outbound = controller.updatePlacement(
            changed, logicalState: .travellingToPresentation, sessionID: sessionID
        )
        XCTAssertEqual(controller.panelOriginForTesting, origin)
        XCTAssertTrue(outbound.motionWasRetargeted)

        let home = controller.updatePlacement(
            initial, logicalState: .travellingHome, sessionID: sessionID
        )
        XCTAssertEqual(controller.panelOriginForTesting, origin)
        XCTAssertTrue(home.motionWasRetargeted)
    }

    func testActiveCardPlacementRebasePreservesOperationAndDoesNotDismiss() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(sourceName: "test", title: "", message: "")
        let sessionID = PresentationSessionID(generation: 1, notificationID: notification.id)
        var dismissCount = 0
        controller.onDismiss = { dismissCount += 1 }
        _ = controller.updatePlacement(
            above: CGPoint(x: 400, y: 160), offset: 20,
            logicalState: .presentation, dismissalSourceRect: nil
        )
        let task = Task {
            await controller.present(
                notification: notification, preferences: DockCatPreferences(),
                from: .zero, reducedMotion: false, sessionID: sessionID
            )
        }
        await Task.yield()

        let outcome = controller.updatePlacement(
            above: CGPoint(x: 640, y: 260), offset: 30,
            logicalState: .presentation, dismissalSourceRect: nil
        )

        XCTAssertTrue(outcome.animationWasRebased)
        let presentationResult = await task.value
        XCTAssertEqual(presentationResult, .completed)
        XCTAssertEqual(dismissCount, 0)
        controller.forceHide()
    }

    func testCardDismissalRebaseCannotInvokeUserDismissCallback() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(sourceName: "test", title: "", message: "")
        let sessionID = PresentationSessionID(generation: 1, notificationID: notification.id)
        var dismissCount = 0
        controller.onDismiss = { dismissCount += 1 }
        _ = controller.updatePlacement(
            above: CGPoint(x: 400, y: 160), offset: 20,
            logicalState: .presentation, dismissalSourceRect: nil
        )
        let presentationResult = await controller.present(
            notification: notification, preferences: DockCatPreferences(),
            from: .zero, reducedMotion: true, sessionID: sessionID
        )
        XCTAssertEqual(presentationResult, .completed)
        let dismissal = Task {
            await controller.dismissActive(
                toward: CGRect(x: 380, y: 150, width: 20, height: 20),
                reducedMotion: false, sessionID: sessionID
            )
        }
        await Task.yield()

        let outcome = controller.updatePlacement(
            above: CGPoint(x: 700, y: 240), offset: 20,
            logicalState: .presentation,
            dismissalSourceRect: CGRect(x: 680, y: 230, width: 20, height: 20)
        )

        XCTAssertTrue(outcome.animationWasRebased)
        let dismissalResult = await dismissal.value
        XCTAssertEqual(dismissalResult, .completed)
        XCTAssertEqual(dismissCount, 0)
    }

    private func makePlacement(
        sleeping: CGPoint,
        presentation: CGPoint,
        edge: DockEdge = .bottom
    ) -> DockPlacement {
        .init(
            sleepingPoint: sleeping,
            presentationPoint: presentation,
            edge: edge,
            usedDisplayFallback: false
        )
    }
}
