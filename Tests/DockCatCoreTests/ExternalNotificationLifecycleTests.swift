import XCTest
@testable import DockCatCore

final class ExternalNotificationLifecycleTests: XCTestCase, @unchecked Sendable {
    private func external(_ id: String = "item", message: String = "body") -> ExternalNotification {
        let identity = ExternalNotificationIdentity(sourceNamespace: "test.ax", stableItemIdentifier: id)
        return .init(identity: identity, notification: .init(sourceName: "Test", title: "Title", message: message,
            presentation: .persistent, externalIdentity: identity))
    }

    func testAppearanceNoOpUpdateMeaningfulUpdateAndRemoval() async {
        let tracker = ExternalNotificationLifecycleTracker()
        let first = external()
        let appeared = await tracker.observe(first); XCTAssertEqual(appeared, .event(.appeared(first)))
        let unchanged = await tracker.observe(first); XCTAssertEqual(unchanged, .unchanged)
        let changed = external(message: "changed")
        let updated = await tracker.observe(changed); XCTAssertEqual(updated, .event(.updated(changed)))
        let removed = await tracker.remove(first.identity); XCTAssertEqual(removed, .event(.disappeared(first.identity)))
        let duplicateRemoval = await tracker.remove(first.identity); XCTAssertEqual(duplicateRemoval, .unsupportedOrdering)
    }

    func testReconciliationPreservesSilentItemsAndShutdownIsDeterministic() async {
        final class TimeBox: @unchecked Sendable { var value = Date(timeIntervalSince1970: 0) }
        let time = TimeBox()
        let tracker = ExternalNotificationLifecycleTracker(capacity: 2, reconciliationTimeout: 5, now: { time.value })
        _ = await tracker.observe(external("a")); _ = await tracker.observe(external("b"))
        let overflow = await tracker.observe(external("c")); XCTAssertEqual(overflow, .unsupportedOrdering)
        time.value = Date(timeIntervalSince1970: 6)
        let reconciled = await tracker.reconcile(); XCTAssertTrue(reconciled.isEmpty)
        let countBeforeStop = await tracker.count(); XCTAssertEqual(countBeforeStop, 2)
        let stopped = await tracker.sourceStopped()
        XCTAssertEqual(stopped, [.disappeared(external("a").identity), .disappeared(external("b").identity)])
        let count = await tracker.count(); XCTAssertEqual(count, 0)
    }

    func testExternalQueueMutationsPreserveFIFOAndInternalUUID() async {
        let queue = NotificationQueue(limit: 3), first = external("a"), second = external("b")
        let inserted = await queue.enqueueAppeared(first.notification); XCTAssertEqual(inserted, .inserted)
        let duplicate = await queue.enqueueAppeared(first.notification); XCTAssertEqual(duplicate, .duplicate)
        let insertedSecond = await queue.enqueueAppeared(second.notification); XCTAssertEqual(insertedSecond, .inserted)
        let changed = external("b", message: "new")
        let update = await queue.updateExternal(changed.notification); XCTAssertEqual(update, .updatedPending)
        let removePending = await queue.removeExternal(first.identity); XCTAssertEqual(removePending, .removedPending)
        let next = await queue.next(); XCTAssertEqual(next?.message, "new")
        let removeCurrent = await queue.removeExternal(second.identity); XCTAssertEqual(removeCurrent, .removedCurrent)
        let missing = await queue.removeExternal(second.identity); XCTAssertEqual(missing, .notFound)
    }
}
