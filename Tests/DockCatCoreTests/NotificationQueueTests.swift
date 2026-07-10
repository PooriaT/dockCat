import XCTest
@testable import DockCatCore

final class NotificationQueueTests: XCTestCase {
    func testFIFOAndCompletion() async {
        let queue = DockCatCore.NotificationQueue(limit: 3)
        let first = DockCatNotification(sourceName: "T", title: "1", message: "")
        let second = DockCatNotification(sourceName: "T", title: "2", message: "")
        let firstResult = await queue.enqueue(first)
        let secondResult = await queue.enqueue(second)
        let dequeuedFirst = await queue.next()
        XCTAssertEqual(firstResult, .accepted)
        XCTAssertEqual(secondResult, .accepted)
        XCTAssertEqual(dequeuedFirst, first)
        await queue.completeCurrent()
        let dequeuedSecond = await queue.next()
        XCTAssertEqual(dequeuedSecond, second)
        await queue.completeCurrent()
        let oldDuplicate = await queue.enqueue(first)
        XCTAssertEqual(oldDuplicate, .duplicate)
    }
    func testDuplicateAndLimit() async {
        let queue = DockCatCore.NotificationQueue(limit: 1)
        let item = DockCatNotification(sourceName: "T", title: "1", message: "")
        let accepted = await queue.enqueue(item)
        let duplicate = await queue.enqueue(item)
        let full = await queue.enqueue(.init(sourceName: "T", title: "2", message: ""))
        XCTAssertEqual(accepted, .accepted)
        XCTAssertEqual(duplicate, .duplicate)
        XCTAssertEqual(full, .full)
    }
    func testPausePreservesQueue() async {
        let queue = DockCatCore.NotificationQueue()
        let item = DockCatNotification(sourceName: "T", title: "1", message: "")
        _ = await queue.enqueue(item)
        await queue.setPaused(true)
        let pausedNext = await queue.next()
        let count = await queue.count()
        XCTAssertNil(pausedNext)
        XCTAssertEqual(count, 1)
        await queue.setPaused(false)
        let resumedNext = await queue.next()
        XCTAssertEqual(resumedNext, item)
    }
}
