import XCTest
@testable import DockCatCore

final class CardQueueContextTests: XCTestCase, @unchecked Sendable {
    func testNegativeAndZeroPendingAreHidden() {
        XCTAssertEqual(
            CardQueueContext(pendingCount: -4, isDeliveryPaused: true),
            CardQueueContext(pendingCount: 0, isDeliveryPaused: true)
        )
        XCTAssertNil(CardQueueContext.empty.visibleText)
        XCTAssertFalse(CardQueueContext.empty.isVisible)
    }

    func testSingularAndPluralCopyAreDeterministic() {
        XCTAssertEqual(
            CardQueueContext(pendingCount: 1, isDeliveryPaused: false).visibleText,
            "1 more notification"
        )
        XCTAssertEqual(
            CardQueueContext(pendingCount: 3, isDeliveryPaused: false).visibleText,
            "3 more notifications"
        )
    }

    func testPauseCopyAppearsOnlyWithPendingItems() {
        XCTAssertEqual(
            CardQueueContext(pendingCount: 2, isDeliveryPaused: true).visibleText,
            "2 waiting · delivery paused"
        )
        XCTAssertNil(
            CardQueueContext(pendingCount: 0, isDeliveryPaused: true).visibleText
        )
    }

    func testAuthoritativeSnapshotTracksAcceptedMutationsOnly() async {
        let queue = DockCatCore.NotificationQueue()
        let first = DockCatNotification(
            sourceName: "Example", title: "First", message: ""
        )
        let second = DockCatNotification(
            sourceName: "Example", title: "Second", message: ""
        )
        let accepted = await queue.enqueue(first)
        let duplicate = await queue.enqueue(first)
        XCTAssertEqual(duplicate.revision, accepted.revision)
        let afterDuplicate = await queue.snapshot()
        XCTAssertEqual(
            afterDuplicate.cardQueueContext,
            .init(pendingCount: 1, isDeliveryPaused: false)
        )

        _ = await queue.enqueue(second)
        _ = await queue.claimNext()
        let afterClaim = await queue.snapshot()
        XCTAssertEqual(
            afterClaim.cardQueueContext,
            .init(pendingCount: 1, isDeliveryPaused: false)
        )

        _ = await queue.setPaused(true)
        let afterPause = await queue.snapshot()
        XCTAssertEqual(
            afterPause.cardQueueContext,
            .init(pendingCount: 1, isDeliveryPaused: true)
        )

        _ = await queue.clearForGlobalDisable()
        let afterClear = await queue.snapshot()
        XCTAssertEqual(afterClear.cardQueueContext, .empty)
    }
}
