import XCTest
@testable import DockCatCore

final class CatStateMachineTests: XCTestCase {
    func testFullTransientFlowReachesSleeping() {
        var machine = CatStateMachine()
        let events: [CatEvent] = [
            .notificationAvailable, .animationCompleted, .animationCompleted,
            .animationCompleted, .cardPresented, .transientExpired, .queueEmpty,
            .cardDismissed, .animationCompleted, .animationCompleted,
        ]

        for event in events { assertAccepted(&machine, event) }

        XCTAssertEqual(machine.state, .sleeping)
    }

    func testFullPersistentUserDismissalFlowReachesSleeping() {
        var machine = CatStateMachine()
        let events: [CatEvent] = [
            .notificationAvailable, .animationCompleted, .animationCompleted,
            .animationCompleted, .cardPresented, .userDismissed, .queueEmpty,
            .cardDismissed, .animationCompleted, .animationCompleted,
        ]
        for event in events { assertAccepted(&machine, event) }
        XCTAssertEqual(machine.state, .sleeping)
    }

    func testQueuedReplacementRemainsAtPresentation() {
        var machine = waitingMachine()
        assertAccepted(&machine, .userDismissed, next: .preparingNextNotification, effect: .selectNextQueueAction)
        assertAccepted(&machine, .nextNotificationAvailable, next: .presenting, effect: .replaceActiveCard)
        assertAccepted(&machine, .cardPresented, next: .waitingForDismissal, effect: .enterWaitingState)
        XCTAssertEqual(machine.state, .waitingForDismissal)
    }

    func testExternalUpdateAndDisappearanceUsePresentationOrdering() {
        var machine = waitingMachine()
        assertAccepted(&machine, .notificationUpdated, next: .presenting, effect: .replaceActiveCard)
        assertAccepted(&machine, .cardPresented, next: .waitingForDismissal, effect: .enterWaitingState)
        assertAccepted(&machine, .sourceDisappeared, next: .preparingNextNotification, effect: .selectNextQueueAction)
    }

    func testCardDismissalIsRequiredBeforeWalkingHome() {
        var machine = waitingMachine()
        assertAccepted(&machine, .userDismissed)
        assertAccepted(&machine, .queueEmpty, next: .dismissingCard, effect: .dismissExpandedCard)
        let stateBeforeRejection = machine.state
        XCTAssertRejected(machine.handle(.animationCompleted), reason: .invalidEventForState)
        XCTAssertEqual(machine.state, stateBeforeRejection)
        assertAccepted(&machine, .cardDismissed, next: .walkingHome, effect: .travelHome)
    }

    func testPauseRecordsAndResumeRestoresEveryPriorState() {
        for state in CatState.allCases where state != .paused {
            var machine = CatStateMachine(state: state)
            assertAccepted(&machine, .pause, next: .paused, effect: .pauseVisualWork)
            assertAccepted(&machine, .resume, next: state, effect: .resumePriorWork)
        }
    }

    func testDuplicatePauseAndInvalidResumeAreDeterministic() {
        var machine = CatStateMachine()
        XCTAssertRejected(machine.handle(.resume), reason: .notPaused)
        assertAccepted(&machine, .pause)
        XCTAssertRejected(machine.handle(.pause), reason: .alreadyPaused)
        XCTAssertEqual(machine.state, .paused)
    }

    func testRejectedTransitionDoesNotMutateStateOrContainEffect() {
        var machine = CatStateMachine()
        let result = machine.handle(.cardPresented)
        XCTAssertRejected(result, reason: .invalidEventForState)
        XCTAssertNil(result.transition)
        XCTAssertEqual(machine.state, .sleeping)
    }

    func testRecoveryResetReturnsMachineToSleepingAndClearsPauseMemory() {
        var machine = CatStateMachine(state: .walkingToPresentation)
        assertAccepted(&machine, .pause)
        let recovery = machine.recoverToSleeping()
        XCTAssertEqual(recovery, .init(previousState: .paused, safeState: .sleeping))
        XCTAssertEqual(machine.state, .sleeping)
        XCTAssertRejected(machine.handle(.resume), reason: .notPaused)
        assertAccepted(&machine, .notificationAvailable, next: .waking, effect: .wake)
    }

    private func waitingMachine() -> CatStateMachine {
        var machine = CatStateMachine()
        for event in [
            CatEvent.notificationAvailable, .animationCompleted, .animationCompleted,
            .animationCompleted, .cardPresented,
        ] { assertAccepted(&machine, event) }
        return machine
    }

    private func assertAccepted(
        _ machine: inout CatStateMachine,
        _ event: CatEvent,
        next: CatState? = nil,
        effect: CatCoordinatorEffect? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = machine.handle(event)
        guard case .accepted(let transition) = result else {
            return XCTFail("Expected acceptance for \(event), got \(result)", file: file, line: line)
        }
        if let next { XCTAssertEqual(transition.nextState, next, file: file, line: line) }
        if let effect { XCTAssertEqual(transition.effect, effect, file: file, line: line) }
    }
}

private func XCTAssertRejected(
    _ result: CatTransitionResult,
    reason: CatTransitionRejectionReason,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .rejected(let rejection) = result else {
        return XCTFail("Expected rejection, got \(result)", file: file, line: line)
    }
    XCTAssertEqual(rejection.reason, reason, file: file, line: line)
}
