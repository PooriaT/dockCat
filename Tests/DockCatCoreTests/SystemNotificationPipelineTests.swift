import XCTest
@testable import DockCatCore

final class SystemNotificationPipelineTests: XCTestCase, @unchecked Sendable {
    func testDuplicateDoesNotReachQueueAndInternalEventsRemainDirect() async {
        let queue = NotificationQueue(limit: 5)
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let accepted = await pipeline.ingest(AXFixtures.banner(sequence: 1), transientDuration: 7)
        let duplicate = await pipeline.ingest(AXFixtures.banner(sequence: 2), transientDuration: 7)
        let initialCount = await queue.count()
        XCTAssertEqual(accepted, .enqueued); XCTAssertEqual(duplicate, .duplicate); XCTAssertEqual(initialCount, 1)
        let internalItem = DockCatNotification(sourceName: "Simulator", title: "Synthetic", message: "Direct event")
        let internalResult = await queue.enqueue(internalItem), total = await queue.count()
        XCTAssertEqual(internalResult, .accepted); XCTAssertEqual(total, 2)
        let first = await queue.next()
        XCTAssertEqual(first?.presentation, .transient(duration: 7)); XCTAssertNil(first?.actionURL)
        XCTAssertNotNil(first?.externalIdentity)
    }
    func testQueueFullRollsBackDeduplicationReservation() async {
        let queue = NotificationQueue(limit: 1); _ = await queue.enqueue(.init(sourceName: "Internal", title: "", message: "Invented"))
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let full = await pipeline.ingest(AXFixtures.banner(), transientDuration: 5); XCTAssertEqual(full, .queueFull)
        _ = await queue.next(); _ = await queue.completeCurrent()
        let retried = await pipeline.ingest(AXFixtures.banner(sequence: 2), transientDuration: 5); XCTAssertEqual(retried, .enqueued)
    }
    func testSelfOriginAndWidgetNeverReachQueue() async {
        let queue = NotificationQueue()
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let own = await pipeline.ingest(AXFixtures.banner(bundle: "com.example.DockCat"), transientDuration: 5)
        let widget = await pipeline.ingest(AXFixtures.widget, transientDuration: 5)
        let count = await queue.count()
        XCTAssertEqual(own, .rejected(.excludedOrigin)); XCTAssertEqual(widget, .rejected(.unrelatedStructure)); XCTAssertEqual(count, 0)
    }
    func testDestroyedSnapshotNeverEnqueues() async {
        let queue = NotificationQueue()
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: "com.example.DockCat")
        let source = AXFixtures.banner()
        let destroyed = AccessibilityNotificationSnapshot(origin: source.origin, observationKind: .destroyed,
            captureSequence: source.captureSequence, root: source.root,
            observedElementIdentifier: source.observedElementIdentifier)
        let result = await pipeline.ingest(destroyed, transientDuration: 5)
        let count = await queue.count()
        XCTAssertEqual(result, .rejected(.disappeared)); XCTAssertEqual(count, 0)
    }
}
