import XCTest
@testable import DockCatCore

final class ManualPresentationClockTests: XCTestCase, @unchecked Sendable {
    func testAdvancingResumesOnlyReachedDeadlines() async throws {
        let clock = ManualPresentationClock()
        let first = Task { try await clock.sleep(until: .zero + .seconds(2)) }
        let second = Task { try await clock.sleep(until: .zero + .seconds(3)) }
        await waitForWaiters(2, on: clock)

        await clock.advance(by: .seconds(2))
        try await first.value
        let waitersAfterFirst = await clock.pendingWaiterCount
        XCTAssertEqual(waitersAfterFirst, 1)

        await clock.advance(by: .seconds(1))
        try await second.value
        let waitersAfterSecond = await clock.pendingWaiterCount
        XCTAssertEqual(waitersAfterSecond, 0)
    }

    func testCancellingSleepRemovesWaiter() async {
        let clock = ManualPresentationClock()
        let sleeper = Task { try await clock.sleep(until: .zero + .seconds(10)) }
        await waitForWaiters(1, on: clock)
        sleeper.cancel()

        do {
            try await sleeper.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let waiters = await clock.pendingWaiterCount
        XCTAssertEqual(waiters, 0)
    }
}

@MainActor
final class PresentationSessionTests: XCTestCase {
    func testReplacementCreatesGenerationAndRejectsOldCallbacks() {
        let coordinator = PresentationSessionCoordinator(clock: ManualPresentationClock())
        let firstID = UUID(), secondID = UUID()
        let first = coordinator.startSession(notificationID: firstID, transientDuration: .seconds(5))
        let firstTask = Task<Void, Never> { await Task.yield() }
        coordinator.register(firstTask, as: .choreography, for: first)
        let second = coordinator.startSession(notificationID: secondID, transientDuration: nil)

        XCTAssertGreaterThan(second.generation, first.generation)
        XCTAssertEqual(coordinator.validate(first), .staleSession)
        XCTAssertEqual(coordinator.validate(second, notificationID: secondID), .valid)
        XCTAssertTrue(firstTask.isCancelled)
    }

    func testContentRevisionRejectsStaleReplacementCompletion() {
        let coordinator = PresentationSessionCoordinator(clock: ManualPresentationClock())
        let id = coordinator.startSession(notificationID: UUID(), transientDuration: .seconds(5))
        XCTAssertEqual(coordinator.replaceContent(for: id, transientDuration: .seconds(7)), 1)
        XCTAssertEqual(coordinator.validate(id, contentRevision: 0), .staleContentRevision)
        XCTAssertEqual(coordinator.validate(id, contentRevision: 1), .valid)
    }

    func testTimerStartsAfterPresentationAndExpiresExactlyOnce() async {
        let clock = ManualPresentationClock()
        let coordinator = PresentationSessionCoordinator(clock: clock)
        let id = coordinator.startSession(notificationID: UUID(), transientDuration: .seconds(5))
        var expiries = 0

        let initialWaiters = await clock.pendingWaiterCount
        XCTAssertEqual(initialWaiters, 0)
        await coordinator.cardPresented(for: id) { _ in expiries += 1 }
        await waitForWaiters(1, on: clock)
        await clock.advance(by: .seconds(4))
        await drainTasks()
        XCTAssertEqual(expiries, 0)

        await clock.advance(by: .seconds(1))
        await drainTasks()
        XCTAssertEqual(expiries, 1)
        await clock.advance(by: .seconds(20))
        await drainTasks()
        XCTAssertEqual(expiries, 1)
    }

    func testPersistentPresentationNeverSchedulesTimer() async {
        let clock = ManualPresentationClock()
        let coordinator = PresentationSessionCoordinator(clock: clock)
        let id = coordinator.startSession(notificationID: UUID(), transientDuration: nil)
        await coordinator.cardPresented(for: id) { _ in XCTFail("Persistent session expired") }
        let waiters = await clock.pendingWaiterCount
        XCTAssertEqual(waiters, 0)
    }

    func testPauseResumePreservesRemainingTimeAcrossCycles() async {
        let clock = ManualPresentationClock()
        let coordinator = PresentationSessionCoordinator(clock: clock)
        let id = coordinator.startSession(notificationID: UUID(), transientDuration: .seconds(10))
        var expiries = 0
        let expire: @MainActor @Sendable (PresentationSessionID) -> Void = { _ in expiries += 1 }
        await coordinator.cardPresented(for: id, onExpiry: expire)
        await waitForWaiters(1, on: clock)

        await clock.advance(by: .seconds(3))
        await coordinator.pause(for: id)
        XCTAssertEqual(coordinator.snapshot()?.remainingTransientDuration, .seconds(7))
        let pausedWaiters = await clock.pendingWaiterCount
        XCTAssertEqual(pausedWaiters, 0)
        await clock.advance(by: .seconds(50))
        XCTAssertEqual(expiries, 0)

        await coordinator.resume(for: id, onExpiry: expire)
        await waitForWaiters(1, on: clock)
        await clock.advance(by: .seconds(2))
        await coordinator.pause(for: id)
        XCTAssertEqual(coordinator.snapshot()?.remainingTransientDuration, .seconds(5))
        await coordinator.resume(for: id, onExpiry: expire)
        await waitForWaiters(1, on: clock)
        await clock.advance(by: .seconds(5))
        await drainTasks()
        XCTAssertEqual(expiries, 1)
    }

    func testPauseBeforePresentationDoesNotCreateTimer() async {
        let clock = ManualPresentationClock()
        let coordinator = PresentationSessionCoordinator(clock: clock)
        let id = coordinator.startSession(notificationID: UUID(), transientDuration: .seconds(5))
        await coordinator.pause(for: id)
        await clock.advance(by: .seconds(100))
        let waitersBeforeResume = await clock.pendingWaiterCount
        XCTAssertEqual(waitersBeforeResume, 0)
        await coordinator.resume(for: id) { _ in XCTFail("Not presented") }
        let waitersAfterResume = await clock.pendingWaiterCount
        XCTAssertEqual(waitersAfterResume, 0)
    }

    func testResumeWithZeroRemainingExpiresOnce() async {
        let clock = ManualPresentationClock()
        let coordinator = PresentationSessionCoordinator(clock: clock)
        let id = coordinator.startSession(notificationID: UUID(), transientDuration: .seconds(5))
        var expiries = 0
        let expire: @MainActor @Sendable (PresentationSessionID) -> Void = { _ in expiries += 1 }
        await coordinator.cardPresented(for: id, onExpiry: expire)
        await waitForWaiters(1, on: clock)

        // Advance the clock and pause in the same main-actor turn, before the resumed
        // timeout task can deliver its callback.
        await clock.advance(by: .seconds(5))
        await coordinator.pause(for: id)
        XCTAssertEqual(coordinator.snapshot()?.remainingTransientDuration, .zero)
        await coordinator.resume(for: id, onExpiry: expire)
        await drainTasks()
        XCTAssertEqual(expiries, 1)
    }

    func testReplacingSessionCancelsTimerAndRemovesManualWaiter() async {
        let clock = ManualPresentationClock()
        let coordinator = PresentationSessionCoordinator(clock: clock)
        let first = coordinator.startSession(notificationID: UUID(), transientDuration: .seconds(20))
        await coordinator.cardPresented(for: first) { _ in XCTFail("Stale timer fired") }
        await waitForWaiters(1, on: clock)

        let second = coordinator.startSession(notificationID: UUID(), transientDuration: nil)
        await waitForWaiters(0, on: clock)
        XCTAssertEqual(coordinator.validate(first), .staleSession)
        XCTAssertEqual(coordinator.validate(second), .valid)
    }

    func testPhaseAndNotificationValidationAreCentralized() {
        let notificationID = UUID()
        let coordinator = PresentationSessionCoordinator(clock: ManualPresentationClock())
        let id = coordinator.startSession(
            notificationID: notificationID, transientDuration: nil, phase: .pickingUp
        )

        XCTAssertEqual(coordinator.validate(id, notificationID: UUID()), .wrongNotification)
        XCTAssertEqual(coordinator.validate(id, phase: .waking), .wrongPhase)
        XCTAssertEqual(
            coordinator.validate(id, notificationID: notificationID, phase: .pickingUp),
            .valid
        )
    }

    func testDismissalRaceHasOneWinner() async {
        let coordinator = PresentationSessionCoordinator(clock: ManualPresentationClock())
        let id = coordinator.startSession(notificationID: UUID(), transientDuration: .seconds(5))
        await coordinator.cardPresented(for: id) { _ in }

        XCTAssertEqual(coordinator.beginDismissal(sessionID: id, cause: .userClose), .began(.userClose))
        XCTAssertEqual(coordinator.beginDismissal(sessionID: id, cause: .transientExpiry), .alreadyDismissing(.userClose))
        XCTAssertEqual(coordinator.beginDismissal(sessionID: id, cause: .sourceDisappearance), .alreadyDismissing(.userClose))
    }

    func testDeferredDisappearanceWinsAndDoesNotLeakToReplacement() {
        let coordinator = PresentationSessionCoordinator(clock: ManualPresentationClock())
        let first = coordinator.startSession(notificationID: UUID(), transientDuration: nil)
        coordinator.deferExternalUpdate(notificationID: first.notificationID, for: first)
        coordinator.deferExternalDisappearance(for: first)
        XCTAssertTrue(coordinator.snapshot()?.hasPendingExternalDisappearance == true)
        XCTAssertNil(coordinator.snapshot()?.pendingExternalUpdateID)

        let second = coordinator.startSession(notificationID: UUID(), transientDuration: nil)
        XCTAssertFalse(coordinator.snapshot()?.hasPendingExternalDisappearance == true)
        XCTAssertNil(coordinator.snapshot()?.pendingExternalUpdateID)
        XCTAssertEqual(coordinator.validate(first), .staleSession)
        XCTAssertEqual(coordinator.validate(second), .valid)
    }
}

private func waitForWaiters(_ count: Int, on clock: ManualPresentationClock) async {
    for _ in 0..<100 {
        if await clock.pendingWaiterCount == count { return }
        await Task.yield()
    }
    XCTFail("Manual clock did not reach \(count) waiters")
}

@MainActor
private func drainTasks() async {
    for _ in 0..<10 { await Task.yield() }
}
