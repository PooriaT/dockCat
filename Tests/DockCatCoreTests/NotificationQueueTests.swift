import XCTest
@testable import DockCatCore

final class NotificationQueueTests: XCTestCase, @unchecked Sendable {
    private func item(_ title: String, id: UUID = UUID()) -> DockCatNotification {
        .init(id: id, sourceName: "T", title: title, message: "")
    }

    private func external(_ key: String, message: String = "body") -> DockCatNotification {
        let identity = ExternalNotificationIdentity(sourceNamespace: "tests", stableItemIdentifier: key)
        return .init(sourceName: "T", title: key, message: message, externalIdentity: identity)
    }

    func testClaimFromIdlePromotesFirstPendingAndRepeatedClaimKeepsCurrent() async {
        let queue = DockCatCore.NotificationQueue()
        let first = item("1"), second = item("2")
        let firstEnqueue = await queue.enqueue(first)
        let secondEnqueue = await queue.enqueue(second)
        XCTAssertTrue(firstEnqueue.wasAccepted)
        XCTAssertTrue(secondEnqueue.wasAccepted)

        let firstClaim = await queue.claimNext()
        guard case .promoted(let promoted, let promotedRevision) = firstClaim else {
            return XCTFail("Expected a promotion")
        }
        XCTAssertEqual(promoted, first)

        let repeated = await queue.claimNext()
        guard case .current(let authoritative, let repeatedRevision) = repeated else {
            return XCTFail("Expected the existing current item")
        }
        XCTAssertEqual(authoritative, first)
        XCTAssertEqual(repeatedRevision, promotedRevision)
    }

    func testPausedClaimNeverPromotesPending() async {
        let queue = DockCatCore.NotificationQueue()
        let notification = item("1")
        _ = await queue.enqueue(notification)
        _ = await queue.setPaused(true)

        guard case .paused(let current, let pendingCount, _) = await queue.claimNext() else {
            return XCTFail("Expected paused")
        }
        XCTAssertNil(current)
        XCTAssertEqual(pendingCount, 1)
        let snapshot = await queue.snapshot()
        XCTAssertNil(snapshot.currentID)
        XCTAssertEqual(snapshot.count, 1)
    }

    func testCompletionAdvanceIsOneAtomicDecision() async {
        let queue = DockCatCore.NotificationQueue()
        let first = item("1"), second = item("2")
        _ = await queue.enqueue(first)
        _ = await queue.enqueue(second)
        _ = await queue.claimNext()

        guard case .advanced(let completed, let next, let revision) =
                await queue.completeCurrent(policy: .advanceImmediately) else {
            return XCTFail("Expected atomic advance")
        }
        XCTAssertEqual(completed, first)
        XCTAssertEqual(next, second)
        let advancedSnapshot = await queue.snapshot()
        XCTAssertEqual(advancedSnapshot.revision, revision)
        guard case .current(let repeated, _) = await queue.claimNext() else {
            return XCTFail("Expected authoritative current")
        }
        XCTAssertEqual(repeated, second)
    }

    func testLeavePendingClearsCurrentWithoutPromotion() async {
        let queue = DockCatCore.NotificationQueue()
        let first = item("1"), second = item("2")
        _ = await queue.enqueue(first)
        _ = await queue.enqueue(second)
        _ = await queue.claimNext()

        guard case .completedWithPending(let completed, let count, _) =
                await queue.completeCurrent(policy: .leavePendingForLater) else {
            return XCTFail("Expected pending work to remain")
        }
        XCTAssertEqual(completed, first)
        XCTAssertEqual(count, 1)
        let pendingSnapshot = await queue.snapshot()
        XCTAssertNil(pendingSnapshot.currentID)
        guard case .promoted(let promoted, _) = await queue.claimNext() else {
            return XCTFail("Expected later promotion")
        }
        XCTAssertEqual(promoted, second)
    }

    func testCompletionWithEmptyPendingReturnsIdle() async {
        let queue = DockCatCore.NotificationQueue()
        let notification = item("1")
        _ = await queue.enqueue(notification)
        _ = await queue.claimNext()
        guard case .completedAndIdle(let completed, _) =
                await queue.completeCurrent(policy: .advanceImmediately) else {
            return XCTFail("Expected idle completion")
        }
        XCTAssertEqual(completed, notification)
        let idleSnapshot = await queue.snapshot()
        XCTAssertEqual(idleSnapshot.count, 0)
    }

    func testCompletionWhilePausedNeverPromotes() async {
        let queue = DockCatCore.NotificationQueue()
        let first = item("1"), second = item("2")
        _ = await queue.enqueue(first)
        _ = await queue.enqueue(second)
        _ = await queue.claimNext()
        _ = await queue.setPaused(true)

        guard case .pausedAfterCompletion(let completed, let count, _) =
                await queue.completeCurrent(policy: .advanceImmediately) else {
            return XCTFail("Expected paused completion")
        }
        XCTAssertEqual(completed, first)
        XCTAssertEqual(count, 1)
        let pausedSnapshot = await queue.snapshot()
        XCTAssertNil(pausedSnapshot.currentID)
    }

    func testActorOrderingAroundCompletionNeverLosesEnqueue() async {
        let queue = DockCatCore.NotificationQueue()
        let first = item("1"), before = item("before"), after = item("after")
        _ = await queue.enqueue(first)
        _ = await queue.claimNext()
        _ = await queue.enqueue(before)
        guard case .advanced(_, let selected, _) = await queue.completeCurrent(policy: .advanceImmediately) else {
            return XCTFail("Expected before item to advance")
        }
        XCTAssertEqual(selected, before)
        let afterEnqueue = await queue.enqueue(after)
        XCTAssertTrue(afterEnqueue.wasAccepted)
        _ = await queue.completeCurrent(policy: .advanceImmediately)
        guard case .current(let final, _) = await queue.claimNext() else {
            return XCTFail("Expected after item to remain")
        }
        XCTAssertEqual(final, after)
    }

    func testPauseRequestsFinishInFinalRequestedState() async {
        let queue = DockCatCore.NotificationQueue()
        _ = await queue.setPaused(true)
        _ = await queue.setPaused(false)
        let final = await queue.setPaused(true)
        XCTAssertTrue(final.isPaused)
        let finalSnapshot = await queue.snapshot()
        XCTAssertTrue(finalSnapshot.isPaused)
    }

    func testExternalUpdateReturnsPayloadAndPendingPositionIsStable() async {
        let queue = DockCatCore.NotificationQueue()
        let first = external("a"), second = external("b")
        _ = await queue.enqueueAppeared(first)
        _ = await queue.enqueueAppeared(second)
        _ = await queue.claimNext()

        let activeUpdate = external("a", message: "active-new")
        guard case .updatedCurrent(let active, _) = await queue.updateExternal(activeUpdate) else {
            return XCTFail("Expected active update")
        }
        XCTAssertEqual(active.id, first.id)
        XCTAssertEqual(active.message, "active-new")

        let pendingUpdate = external("b", message: "pending-new")
        guard case .updatedPending(let pending, let index, _) = await queue.updateExternal(pendingUpdate) else {
            return XCTFail("Expected pending update")
        }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(pending.id, second.id)
        guard case .advanced(_, let next, _) = await queue.completeCurrent(policy: .advanceImmediately) else {
            return XCTFail("Expected updated pending item")
        }
        XCTAssertEqual(next.message, "pending-new")
    }

    func testExternalDisappearanceIsTypedAndIdempotent() async {
        let queue = DockCatCore.NotificationQueue()
        let active = external("active"), pending = external("pending")
        _ = await queue.enqueueAppeared(active)
        _ = await queue.enqueueAppeared(pending)
        _ = await queue.claimNext()

        guard case .removedPending(let removedPending, let index, _) =
                await queue.removeExternal(pending.externalIdentity!) else {
            return XCTFail("Expected pending removal")
        }
        XCTAssertEqual(removedPending.id, pending.id)
        XCTAssertEqual(index, 0)
        guard case .removedCurrent(let removedCurrent, let count, _) =
                await queue.removeExternal(active.externalIdentity!) else {
            return XCTFail("Expected current removal")
        }
        XCTAssertEqual(removedCurrent.id, active.id)
        XCTAssertEqual(count, 0)
        guard case .notFound = await queue.removeExternal(active.externalIdentity!) else {
            return XCTFail("Repeated disappearance must be a no-op")
        }
    }

    func testExternalRemovalRacingCompletionAllowsAuthoritativeNextClaim() async {
        let queue = DockCatCore.NotificationQueue()
        let active = external("active"), pending = external("pending")
        _ = await queue.enqueueAppeared(active)
        _ = await queue.enqueueAppeared(pending)
        _ = await queue.claimNext()

        guard case .removedCurrent(let removed, _, let removalRevision) =
                await queue.removeExternal(active.externalIdentity!) else {
            return XCTFail("Expected external removal to win the race")
        }
        XCTAssertEqual(removed.id, active.id)
        guard case .noCurrent(let completionRevision) =
                await queue.completeCurrent(policy: .advanceImmediately) else {
            return XCTFail("Completion must report the lifecycle race without mutating")
        }
        XCTAssertEqual(completionRevision, removalRevision)

        guard case .promoted(let next, let claimRevision) = await queue.claimNext() else {
            return XCTFail("Coordinator must be able to claim authoritatively after removal")
        }
        XCTAssertEqual(next.id, pending.id)
        XCTAssertGreaterThan(claimRevision, completionRevision)
    }

    func testRevisionChangesOnlyAfterAcceptedMutation() async {
        let queue = DockCatCore.NotificationQueue(limit: 1)
        let first = item("1")
        let initial = await queue.snapshot()
        let accepted = await queue.enqueue(first)
        XCTAssertGreaterThan(accepted.revision, initial.revision)
        let duplicate = await queue.enqueue(first)
        let full = await queue.enqueue(item("2"))
        XCTAssertEqual(duplicate.revision, accepted.revision)
        XCTAssertEqual(full.revision, accepted.revision)
        guard case .promoted(_, let claimedRevision) = await queue.claimNext() else {
            return XCTFail("Expected claim")
        }
        XCTAssertGreaterThan(claimedRevision, accepted.revision)
        guard case .current(_, let repeatedRevision) = await queue.claimNext() else {
            return XCTFail("Expected current")
        }
        XCTAssertEqual(repeatedRevision, claimedRevision)
    }

    func testSnapshotReconcilesProjectionWithoutExposingPendingStorage() async {
        let queue = DockCatCore.NotificationQueue()
        let notification = item("1")
        _ = await queue.enqueue(notification)
        _ = await queue.claimNext()
        let snapshot = await queue.snapshot()
        XCTAssertTrue(snapshot.matches(projectedCurrent: notification))
        XCTAssertFalse(snapshot.matches(projectedCurrent: item("other")))
    }

    func testActiveAndRecentDuplicateTrackingIsBoundedAndEvictsFIFO() async {
        let queue = DockCatCore.NotificationQueue(recentCompletionCapacity: 2)
        let first = item("1"), second = item("2"), third = item("3")
        let firstAccepted = await queue.enqueue(first)
        let activeDuplicate = await queue.enqueue(first)
        XCTAssertTrue(firstAccepted.wasAccepted)
        XCTAssertFalse(activeDuplicate.wasAccepted)

        for notification in [first, second, third] {
            if notification.id != first.id {
                let accepted = await queue.enqueue(notification)
                XCTAssertTrue(accepted.wasAccepted)
            }
            _ = await queue.claimNext()
            _ = await queue.completeCurrent(policy: .leavePendingForLater)
        }
        let bounded = await queue.snapshot()
        XCTAssertEqual(bounded.recentCompletionCount, 2)
        XCTAssertEqual(bounded.recentCompletionCapacity, 2)
        let evictedAccepted = await queue.enqueue(first)
        let retainedDuplicate = await queue.enqueue(second)
        XCTAssertTrue(evictedAccepted.wasAccepted, "Oldest completion should be eligible after eviction")
        XCTAssertFalse(retainedDuplicate.wasAccepted, "Retained completion should remain protected")
    }

    func testRemovingExternalReleasesActiveIDAndLimitChangesPreserveItems() async {
        let queue = DockCatCore.NotificationQueue(limit: 3, recentCompletionCapacity: 0)
        let external = external("a")
        _ = await queue.enqueueAppeared(external)
        _ = await queue.setLimit(1)
        let loweredSnapshot = await queue.snapshot()
        XCTAssertEqual(loweredSnapshot.count, 1)
        let full = await queue.enqueue(item("full"))
        XCTAssertFalse(full.wasAccepted)
        _ = await queue.removeExternal(external.externalIdentity!)
        let reaccepted = await queue.enqueue(external)
        XCTAssertTrue(reaccepted.wasAccepted)
        let raised = await queue.setLimit(4)
        guard case .changed(let previous, let current, _) = raised else {
            return XCTFail("Expected limit change")
        }
        XCTAssertEqual(previous, 1)
        XCTAssertEqual(current, 4)
    }
}
