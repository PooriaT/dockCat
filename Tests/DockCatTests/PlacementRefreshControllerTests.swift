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

    func testOutboundDockEdgeChangeUsesDestinationExclusionAndLiveHandoffSeparately() {
        let controller = CatWindowController()
        let initial = makePlacement(
            sleeping: CGPoint(x: 240, y: 180),
            presentation: CGPoint(x: 500, y: 180)
        )
        _ = controller.updatePlacement(initial, logicalState: .home, sessionID: nil)
        let sessionID = PresentationSessionID(generation: 1, notificationID: UUID())
        let changed = makePlacement(
            sleeping: CGPoint(x: 320, y: 240),
            presentation: CGPoint(x: 710, y: 240),
            edge: .left
        )

        _ = controller.updatePlacement(
            changed, logicalState: .travellingToPresentation, sessionID: sessionID
        )

        XCTAssertEqual(
            controller.presentationExclusionFrame(),
            CGRect(x: 635, y: 205, width: 150, height: 110)
        )
        XCTAssertEqual(
            controller.handoffSourceRect(),
            CGRect(x: 264, y: 206, width: 36, height: 24)
        )
    }

    func testActiveCardPlacementRebasePreservesOperationAndDoesNotDismiss() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(sourceName: "test", title: "", message: "")
        let sessionID = PresentationSessionID(generation: 1, notificationID: notification.id)
        var dismissCount = 0
        controller.onDismiss = { dismissCount += 1 }
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 400, y: 160), offset: 20, revision: 1),
            logicalState: .presentation, dismissalSourceRect: nil
        )
        let task = Task {
            await controller.present(
                notification: notification, preferences: DockCatPreferences(),
                from: .zero, reducedMotion: false, sessionID: sessionID
            )
        }
        await Task.yield()

        let outcome = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 640, y: 260), offset: 30, revision: 2),
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
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 400, y: 160), offset: 20, revision: 1),
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

        let outcome = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 700, y: 240), offset: 20, revision: 2),
            logicalState: .presentation,
            dismissalSourceRect: CGRect(x: 680, y: 230, width: 20, height: 20)
        )

        XCTAssertTrue(outcome.animationWasRebased)
        let dismissalResult = await dismissal.value
        XCTAssertEqual(dismissalResult, .completed)
        XCTAssertEqual(dismissCount, 0)
    }

    func testHiddenCardStoresContextWithoutShowing() {
        let controller = CardWindowController()
        let context = makeCardContext(
            anchor: CGPoint(x: -500, y: 120), revision: 7,
            visibleFrame: CGRect(x: -1_200, y: -200, width: 1_200, height: 900)
        )

        _ = controller.updatePlacementContext(
            context, logicalState: .home, dismissalSourceRect: nil
        )

        XCTAssertEqual(controller.placementRevisionForTesting, 7)
        XCTAssertFalse(controller.panelIsVisibleForTesting)
    }

    func testPresentUsesMeasuredContentSizeAndSelectedScreenCoordinates() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(
            sourceName: "test", title: "Measured", message: "Short"
        )
        let sessionID = PresentationSessionID(
            generation: 1, notificationID: notification.id
        )
        _ = controller.updatePlacementContext(
            makeCardContext(
                anchor: CGPoint(x: -600, y: 80), revision: 1,
                visibleFrame: CGRect(x: -1_200, y: -100, width: 1_200, height: 800)
            ),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )

        let result = await controller.present(
            notification: notification, preferences: DockCatPreferences(),
            from: CGRect(x: -620, y: 60, width: 36, height: 24),
            reducedMotion: true, sessionID: sessionID
        )

        XCTAssertEqual(result, .completed)
        XCTAssertEqual(controller.panelFrameForTesting.size, controller.measuredCardSizeForTesting)
        XCTAssertLessThan(controller.panelFrameForTesting.minX, 0)
        XCTAssertGreaterThanOrEqual(controller.panelFrameForTesting.minX, -1_190)
        controller.forceHide()
    }

    func testReplacementRemeasuresAndChangesFrameHeight() async {
        let controller = CardWindowController()
        let short = DockCatNotification(
            sourceName: "test", title: "Short", message: "Brief"
        )
        let tall = DockCatNotification(
            sourceName: "test",
            title: "A deliberately long title that wraps onto its second available line",
            message: "A long message that fills the available card width and uses several lines so fitting size reflects the replacement content instead of the panel's initial frame.",
            presentation: .persistent,
            actionURL: URL(string: "https://example.com")
        )
        let sessionID = PresentationSessionID(generation: 1, notificationID: short.id)
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 600, y: 100), revision: 1),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )
        _ = await controller.present(
            notification: short, preferences: DockCatPreferences(), from: .zero,
            reducedMotion: true, sessionID: sessionID
        )
        let shortHeight = controller.panelFrameForTesting.height

        let result = await controller.replace(
            notification: tall, preferences: DockCatPreferences(),
            reducedMotion: true, sessionID: sessionID
        )

        XCTAssertEqual(result, .completed)
        let tallHeight = controller.panelFrameForTesting.height
        XCTAssertGreaterThan(tallHeight, shortHeight)
        XCTAssertEqual(controller.panelFrameForTesting.size, controller.measuredCardSizeForTesting)

        _ = await controller.replace(
            notification: short,
            preferences: DockCatPreferences(),
            reducedMotion: true,
            sessionID: sessionID
        )
        XCTAssertLessThan(controller.panelFrameForTesting.height, tallHeight)
        XCTAssertEqual(controller.panelFrameForTesting.height, shortHeight, accuracy: 1)
        controller.forceHide()
    }

    func testQueueFooterResizesVisibleCardInPlaceAndRejectsStaleRevision() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(
            sourceName: "Example", title: "Queued", message: "Short message"
        )
        let sessionID = PresentationSessionID(
            generation: 1, notificationID: notification.id
        )
        var dismissCount = 0
        controller.onDismiss = { dismissCount += 1 }
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 600, y: 120), revision: 1),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )
        _ = await controller.present(
            notification: notification,
            preferences: DockCatPreferences(),
            from: .zero,
            reducedMotion: true,
            sessionID: sessionID
        )
        let originalHeight = controller.panelFrameForTesting.height
        let operationSequence = controller.operationSequenceForTesting

        controller.updateQueueContext(
            .init(pendingCount: 2, isDeliveryPaused: false), revision: 10
        )
        let queuedHeight = controller.panelFrameForTesting.height

        XCTAssertGreaterThan(queuedHeight, originalHeight)
        XCTAssertEqual(controller.installedNotificationIDForTesting, notification.id)
        XCTAssertEqual(controller.operationSequenceForTesting, operationSequence)
        XCTAssertEqual(dismissCount, 0)

        controller.updateQueueContext(.empty, revision: 9)
        XCTAssertEqual(controller.queueContextForTesting.pendingCount, 2)
        XCTAssertEqual(controller.queueContextRevisionForTesting, 10)

        controller.updateQueueContext(.empty, revision: 11)
        XCTAssertEqual(controller.panelFrameForTesting.height, originalHeight)
        XCTAssertEqual(controller.operationSequenceForTesting, operationSequence)
        XCTAssertEqual(dismissCount, 0)
        controller.forceHide()
    }

    func testLongBodyIsInternallyScrollableAndPanelBounded() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(
            sourceName: "Example",
            title: "Long body",
            message: String(repeating: "Invented long body content. ", count: 300),
            presentation: .persistent,
            actionURL: URL(string: "https://example.com")
        )
        let sessionID = PresentationSessionID(
            generation: 1, notificationID: notification.id
        )
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 600, y: 120), revision: 1),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )

        _ = await controller.present(
            notification: notification,
            preferences: DockCatPreferences(),
            from: .zero,
            reducedMotion: true,
            sessionID: sessionID
        )
        for _ in 0..<5 { await Task.yield() }

        XCTAssertTrue(controller.layoutPlanForTesting.bodyScrolls)
        XCTAssertGreaterThan(controller.layoutPlanForTesting.bodyViewportHeight, 0)
        XCTAssertLessThanOrEqual(
            controller.panelFrameForTesting.height,
            CardLayoutMetrics.maximumHeight
        )
        controller.forceHide()
    }

    func testStableVisibleCardFollowsNewestPlacementAndRejectsStaleRevision() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(
            sourceName: "test", title: "Stable", message: "Card"
        )
        let sessionID = PresentationSessionID(
            generation: 1, notificationID: notification.id
        )
        var dismissCount = 0
        controller.onDismiss = { dismissCount += 1 }
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 500, y: 100), revision: 1),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )
        _ = await controller.present(
            notification: notification, preferences: DockCatPreferences(), from: .zero,
            reducedMotion: true, sessionID: sessionID
        )
        let newest = makeCardContext(
            anchor: CGPoint(x: -500, y: 180), edge: .left, revision: 3,
            visibleFrame: CGRect(x: -1_200, y: -100, width: 1_200, height: 800)
        )
        _ = controller.updatePlacementContext(
            newest, logicalState: .presentation, dismissalSourceRect: nil
        )
        let newestFrame = controller.panelFrameForTesting

        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 900, y: 100), revision: 2),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )

        XCTAssertEqual(controller.placementRevisionForTesting, 3)
        XCTAssertEqual(controller.panelFrameForTesting, newestFrame)
        XCTAssertLessThan(newestFrame.minX, 0)
        XCTAssertEqual(dismissCount, 0)
        controller.forceHide()
    }

    func testCancelledPresentationRestoresLatestValidPlannedFrame() async {
        let controller = CardWindowController()
        let notification = DockCatNotification(
            sourceName: "test", title: "Cancellation", message: "Card"
        )
        let sessionID = PresentationSessionID(
            generation: 1, notificationID: notification.id
        )
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 400, y: 100), revision: 1),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )
        let task = Task {
            await controller.present(
                notification: notification, preferences: DockCatPreferences(),
                from: .zero, reducedMotion: false, sessionID: sessionID
            )
        }
        await Task.yield()
        _ = controller.updatePlacementContext(
            makeCardContext(anchor: CGPoint(x: 800, y: 180), revision: 2),
            logicalState: .presentation,
            dismissalSourceRect: nil
        )
        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(
            controller.panelFrameForTesting,
            controller.stableCardFrameForTesting
        )
        XCTAssertEqual(controller.placementRevisionForTesting, 2)
    }

    private func makePlacement(
        sleeping: CGPoint,
        presentation: CGPoint,
        edge: DockEdge = .bottom
    ) -> DockPlacement {
        .init(
            sleepingPoint: sleeping,
            presentationPoint: presentation,
            baseSleepingPoint: sleeping,
            basePresentationPoint: presentation,
            edge: edge,
            geometryConfidence: .observedVisibleFrameInset,
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleScreenFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876),
            displayIdentity: .init(value: "test-display", quality: .stableUUID),
            displayName: "Test Display",
            requestedDisplayAvailable: true,
            usedDisplayFallback: false,
            migratedSelection: nil
        )
    }

    private func makeCardContext(
        anchor: CGPoint,
        edge: DockEdge = .bottom,
        offset: Double = 14,
        revision: UInt64,
        visibleFrame: CGRect = CGRect(x: 0, y: 24, width: 1_440, height: 876)
    ) -> CardPlacementContext {
        CardPlacementContext(
            presentationAnchor: anchor,
            dockEdge: edge,
            visibleScreenFrame: visibleFrame,
            catExclusionFrame: CGRect(
                x: anchor.x + 24, y: anchor.y + 26, width: 36, height: 24
            ),
            offset: offset,
            placementRevision: revision
        )
    }
}
