import XCTest
@testable import DockCatCore

final class SystemNotificationPipelineTests: XCTestCase, @unchecked Sendable {
    func testDuplicateDoesNotReachQueueAndInternalEventsRemainDirect() async {
        let queue = DockCatCore.NotificationQueue(limit: 5)
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let accepted = await pipeline.ingest(AXFixtures.banner(sequence: 1), transientDuration: 7)
        let duplicate = await pipeline.ingest(AXFixtures.banner(sequence: 2), transientDuration: 7)
        let initialCount = await queue.snapshot().count
        XCTAssertEqual(accepted, .enqueued); XCTAssertEqual(duplicate, .duplicate); XCTAssertEqual(initialCount, 1)
        let internalItem = DockCatNotification(sourceName: "Simulator", title: "Synthetic", message: "Direct event")
        let internalResult = await queue.enqueue(internalItem), total = await queue.snapshot().count
        XCTAssertTrue(internalResult.wasAccepted); XCTAssertEqual(total, 2)
        guard case .promoted(let first, _) = await queue.claimNext() else { return XCTFail("Expected claim") }
        XCTAssertEqual(first.presentation, .transient(duration: 7)); XCTAssertNil(first.actionURL)
        XCTAssertNotNil(first.externalIdentity)
    }
    func testQueueFullRollsBackDeduplicationReservation() async {
        let queue = DockCatCore.NotificationQueue(limit: 1); _ = await queue.enqueue(.init(sourceName: "Internal", title: "", message: "Invented"))
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let full = await pipeline.ingest(AXFixtures.banner(), transientDuration: 5); XCTAssertEqual(full, .queueFull)
        _ = await queue.claimNext(); _ = await queue.completeCurrent(policy: .leavePendingForLater)
        let retried = await pipeline.ingest(AXFixtures.banner(sequence: 2), transientDuration: 5); XCTAssertEqual(retried, .enqueued)
    }
    func testSelfOriginAndWidgetNeverReachQueue() async {
        let queue = DockCatCore.NotificationQueue()
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let own = await pipeline.ingest(AXFixtures.banner(bundle: "com.example.DockCat"), transientDuration: 5)
        let widget = await pipeline.ingest(AXFixtures.widget, transientDuration: 5)
        let count = await queue.snapshot().count
        XCTAssertEqual(own, .rejected(.excludedOrigin)); XCTAssertEqual(widget, .rejected(.unrelatedStructure)); XCTAssertEqual(count, 0)
    }
    func testDestroyedSnapshotNeverEnqueues() async {
        let queue = DockCatCore.NotificationQueue()
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let source = AXFixtures.banner()
        let destroyed = AccessibilityNotificationSnapshot(origin: source.origin, observationKind: .destroyed,
            captureSequence: source.captureSequence, root: source.root,
            observedElementIdentifier: source.observedElementIdentifier)
        let result = await pipeline.ingest(destroyed, transientDuration: 5)
        let count = await queue.snapshot().count
        XCTAssertEqual(result, .rejected(.disappeared)); XCTAssertEqual(count, 0)
    }

    func testFallbackIdentityDoesNotCollapseSameShapeItems() async {
        func snapshot(sequence: UInt64, observed: String, body: String) -> AccessibilityNotificationSnapshot {
            .init(origin: .init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 42),
                  observationKind: .created, captureSequence: sequence,
                  root: .init(role: "AXGroup", subrole: "AXNotificationBanner", children: [
                    .init(role: "AXStaticText", identifier: "appName", value: "Example"),
                    .init(role: "AXStaticText", identifier: "message", value: body)
                  ]), observedElementIdentifier: observed)
        }
        let queue = DockCatCore.NotificationQueue(), pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "dockcat")
        let first = await pipeline.ingest(snapshot(sequence: 1, observed: "leaf.a", body: "First"), transientDuration: 5); XCTAssertEqual(first, .enqueued)
        let second = await pipeline.ingest(snapshot(sequence: 2, observed: "leaf.b", body: "Second"), transientDuration: 5); XCTAssertEqual(second, .enqueued)
        let count = await queue.snapshot().count; XCTAssertEqual(count, 2)
    }

    func testFallbackIdentityIgnoresPerCallbackDismissalToken() async {
        func snapshot(sequence: UInt64, token: String) -> AccessibilityNotificationSnapshot {
            .init(origin: .init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 42),
                  observationKind: .created, captureSequence: sequence,
                  root: .init(role: "AXGroup", subrole: "AXNotificationBanner", children: [
                    .init(role: "AXStaticText", identifier: "appName", value: "Example"),
                    .init(role: "AXStaticText", identifier: "message", value: "Same banner")
                  ]), opaqueDismissalTokenIdentifier: token)
        }
        let queue = DockCatCore.NotificationQueue(), pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "dockcat")
        let first = await pipeline.ingest(snapshot(sequence: 1, token: "uuid-1"), transientDuration: 5)
        let repeated = await pipeline.ingest(snapshot(sequence: 2, token: "uuid-2"), transientDuration: 5)
        XCTAssertEqual(first, .enqueued)
        XCTAssertEqual(repeated, .duplicate)
        let count = await queue.snapshot().count; XCTAssertEqual(count, 1)
    }

    func testDescendantDestructionUsesParserSelectedContainerIdentity() async {
        let queue = DockCatCore.NotificationQueue(), pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "dockcat")
        let appeared = AXFixtures.banner()
        let insert = await pipeline.ingest(appeared, transientDuration: 5); XCTAssertEqual(insert, .enqueued)
        guard case .inserted(_, let insertedIndex, let insertedRevision) = insert.queueMutation else {
            return XCTFail("Pipeline must preserve the atomic queue insertion outcome")
        }
        XCTAssertEqual(insertedIndex, 0)
        let destroyed = AccessibilityNotificationSnapshot(
            origin: appeared.origin, observationKind: .destroyed, captureSequence: 2, root: appeared.root,
            observedElementIdentifier: "message")
        let removal = await pipeline.ingest(destroyed, transientDuration: 5); XCTAssertEqual(removal, .removedPending)
        guard case .removedPending(_, let removedIndex, let removedRevision) = removal.queueMutation else {
            return XCTFail("Pipeline must preserve the atomic queue removal outcome")
        }
        XCTAssertEqual(removedIndex, 0)
        XCTAssertGreaterThan(removedRevision, insertedRevision)
        let finalCount = await queue.snapshot().count; XCTAssertEqual(finalCount, 0)
    }
}
