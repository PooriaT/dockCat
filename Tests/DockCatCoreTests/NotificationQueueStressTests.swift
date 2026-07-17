import XCTest
@testable import DockCatCore

private actor AsyncBarrier {
    private let target: Int
    private var arrivals = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(target: Int) { self.target = target }

    func arriveAndWait() async {
        arrivals += 1
        if arrivals == target {
            let continuations = waiters
            waiters.removeAll()
            continuations.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private struct EnqueueOutcome: Sendable {
    let id: UUID
    let result: NotificationQueueEnqueueResult
}

final class NotificationQueueStressTests: XCTestCase, @unchecked Sendable {
    func testConcurrentEnqueuesDrainExactlyOnceAcrossRepeatedScenarios() async {
        for iteration in 0..<20 {
            let queue = DockCatCore.NotificationQueue(limit: 32, recentCompletionCapacity: 8)
            let items = (0..<24).map {
                DockCatNotification(sourceName: "stress", title: "\(iteration)-\($0)", message: "")
            }
            let barrier = AsyncBarrier(target: items.count)
            let results = await withTaskGroup(
                of: EnqueueOutcome.self,
                returning: [EnqueueOutcome].self
            ) { group in
                for item in items {
                    group.addTask {
                        await barrier.arriveAndWait()
                        return EnqueueOutcome(id: item.id, result: await queue.enqueue(item))
                    }
                }
                var values: [EnqueueOutcome] = []
                for await value in group { values.append(value) }
                return values
            }

            XCTAssertEqual(results.filter { $0.result.wasAccepted }.count, items.count)
            let afterEnqueue = await queue.snapshot()
            XCTAssertEqual(afterEnqueue.count, items.count)
            XCTAssertNil(afterEnqueue.currentID)

            var presented: [UUID] = []
            guard case .promoted(let first, _) = await queue.claimNext() else {
                return XCTFail("Expected first promotion")
            }
            presented.append(first.id)
            while true {
                switch await queue.completeCurrent(policy: .advanceImmediately) {
                case .advanced(_, let next, _): presented.append(next.id)
                case .completedAndIdle: break
                default: return XCTFail("Unexpected drain decision")
                }
                if (await queue.snapshot()).count == 0 { break }
            }

            XCTAssertEqual(presented.count, items.count)
            XCTAssertEqual(Set(presented), Set(items.map(\.id)))
            let finalSnapshot = await queue.snapshot()
            XCTAssertEqual(finalSnapshot.recentCompletionCount, 8)
        }
    }

    func testConcurrentMutationBatchPreservesAtomicInvariants() async {
        for iteration in 0..<20 {
            func external(_ key: String, message: String = "body") -> DockCatNotification {
                let identity = ExternalNotificationIdentity(
                    sourceNamespace: "stress", stableItemIdentifier: "\(iteration)-\(key)"
                )
                return .init(sourceName: "stress", title: key, message: message, externalIdentity: identity)
            }

            let queue = DockCatCore.NotificationQueue(limit: 10, recentCompletionCapacity: 4)
            let a = external("a"), b = external("b"), c = external("c")
            let internalItem = DockCatNotification(sourceName: "stress", title: "internal", message: "")
            let extra = DockCatNotification(sourceName: "stress", title: "extra", message: "")
            _ = await queue.enqueueAppeared(a)
            _ = await queue.enqueueAppeared(b)
            _ = await queue.enqueueAppeared(c)
            _ = await queue.enqueue(internalItem)
            guard case .promoted(let first, _) = await queue.claimNext() else {
                return XCTFail("Expected current")
            }
            XCTAssertEqual(first.id, a.id)

            let barrier = AsyncBarrier(target: 5)
            let revisions = await withTaskGroup(
                of: NotificationQueueRevision.self,
                returning: [NotificationQueueRevision].self
            ) { group in
                group.addTask { await barrier.arriveAndWait(); return await queue.setPaused(true).revision }
                group.addTask { await barrier.arriveAndWait(); return await queue.setLimit(2).revision }
                group.addTask {
                    await barrier.arriveAndWait()
                    return await queue.updateExternal(external("b", message: "updated")).revision
                }
                group.addTask {
                    await barrier.arriveAndWait()
                    return await queue.removeExternal(c.externalIdentity!).revision
                }
                group.addTask { await barrier.arriveAndWait(); return await queue.enqueue(extra).revision }
                var values: [NotificationQueueRevision] = []
                for await revision in group { values.append(revision) }
                return values
            }

            let batch = await queue.snapshot()
            XCTAssertLessThanOrEqual(batch.recentCompletionCount, batch.recentCompletionCapacity)
            XCTAssertGreaterThanOrEqual(batch.revision, revisions.max() ?? 0)
            XCTAssertEqual(batch.count, batch.pendingCount + (batch.currentID == nil ? 0 : 1))
            _ = await queue.setPaused(false)
            _ = await queue.setLimit(10)

            var presented: [UUID] = [a.id]
            while true {
                switch await queue.completeCurrent(policy: .advanceImmediately) {
                case .advanced(_, let next, _): presented.append(next.id)
                case .completedAndIdle: break
                default: return XCTFail("Unexpected completion")
                }
                if (await queue.snapshot()).count == 0 { break }
            }
            XCTAssertEqual(presented.count, Set(presented).count)
            XCTAssertTrue(presented.contains(b.id))
            XCTAssertTrue(presented.contains(internalItem.id))
            XCTAssertFalse(presented.contains(c.id), "A removed pending item must never present")
            let final = await queue.snapshot()
            XCTAssertEqual(final.count, 0)
            XCTAssertNil(final.currentID)
            XCTAssertLessThanOrEqual(final.recentCompletionCount, final.recentCompletionCapacity)
        }
    }
}
