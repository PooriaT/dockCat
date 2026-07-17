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
        let queue = DockCatCore.NotificationQueue(limit: 3), first = external("a"), second = external("b")
        guard case .inserted = await queue.enqueueAppeared(first.notification) else { return XCTFail("Expected insert") }
        guard case .duplicate = await queue.enqueueAppeared(first.notification) else { return XCTFail("Expected duplicate") }
        guard case .inserted = await queue.enqueueAppeared(second.notification) else { return XCTFail("Expected insert") }
        let changed = external("b", message: "new")
        guard case .updatedPending(_, let index, _) = await queue.updateExternal(changed.notification) else { return XCTFail("Expected pending update") }
        XCTAssertEqual(index, 1)
        guard case .removedPending(let removed, _, _) = await queue.removeExternal(first.identity) else { return XCTFail("Expected pending removal") }
        XCTAssertEqual(removed.id, first.notification.id)
        guard case .promoted(let next, _) = await queue.claimNext() else { return XCTFail("Expected claim") }
        XCTAssertEqual(next.message, "new")
        guard case .removedCurrent = await queue.removeExternal(second.identity) else { return XCTFail("Expected current removal") }
        guard case .notFound = await queue.removeExternal(second.identity) else { return XCTFail("Expected no-op removal") }
    }
}
