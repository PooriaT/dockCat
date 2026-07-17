import XCTest
@testable import DockCatCore

final class CatStateMachineTests: XCTestCase {
    func testExternalUpdateAndDisappearanceUsePresentationOrdering() {
        var machine = CatStateMachine()
        XCTAssertTrue(machine.handle(.notificationAvailable)); XCTAssertTrue(machine.handle(.animationCompleted))
        XCTAssertTrue(machine.handle(.animationCompleted)); XCTAssertTrue(machine.handle(.animationCompleted)); XCTAssertTrue(machine.handle(.cardPresented))
        XCTAssertTrue(machine.handle(.notificationUpdated)); XCTAssertEqual(machine.state, .presenting)
        XCTAssertTrue(machine.handle(.cardPresented)); XCTAssertTrue(machine.handle(.sourceDisappeared))
        XCTAssertEqual(machine.state, .preparingNextNotification)
    }
    func testFullTransientFlowRequiresCardDismissedBeforeReturnHome() {
        var machine = CatStateMachine()
        let events: [CatEvent] = [.notificationAvailable, .animationCompleted, .animationCompleted, .animationCompleted, .cardPresented, .transientExpired, .queueEmpty, .cardDismissed, .animationCompleted, .animationCompleted]
        for event in events { XCTAssertTrue(machine.handle(event), "Rejected \(event) from \(machine.state)") }
        XCTAssertEqual(machine.state, .sleeping)
    }

    func testQueuedAndPersistentFlowStaysAtPresentation() {
        var machine = CatStateMachine()
        [.notificationAvailable, .animationCompleted, .animationCompleted, .animationCompleted, .cardPresented, .userDismissed, .nextNotificationAvailable, .cardPresented].forEach { XCTAssertTrue(machine.handle($0)) }
        XCTAssertEqual(machine.state, .waitingForDismissal)
    }

    func testExpandedPresentationRejectedBeforeTravelCompletes() {
        var machine = CatStateMachine()
        XCTAssertTrue(machine.handle(.notificationAvailable))
        XCTAssertTrue(machine.handle(.animationCompleted))
        XCTAssertTrue(machine.handle(.animationCompleted))
        XCTAssertEqual(machine.state, .walkingToPresentation)
        XCTAssertFalse(machine.handle(.cardPresented))
    }

    func testCancelledPresentationDoesNotEnterWaiting() {
        var machine = CatStateMachine()
        [.notificationAvailable, .animationCompleted, .animationCompleted, .animationCompleted].forEach { XCTAssertTrue(machine.handle($0)) }
        XCTAssertEqual(machine.state, .presenting)
        XCTAssertFalse(PresentationChoreography.shouldAcceptPresentationCompletion(.cancelled))
        XCTAssertEqual(machine.state, .presenting)
    }

    func testReturnHomeRejectedBeforeCardDismissalCompletion() {
        var machine = CatStateMachine()
        [.notificationAvailable, .animationCompleted, .animationCompleted, .animationCompleted, .cardPresented, .userDismissed, .queueEmpty].forEach { XCTAssertTrue(machine.handle($0)) }
        XCTAssertEqual(machine.state, .dismissingCard)
        XCTAssertFalse(machine.handle(.animationCompleted))
        XCTAssertTrue(machine.handle(.cardDismissed))
        XCTAssertEqual(machine.state, .walkingHome)
    }

    func testInvalidTransitionAndPauseResume() {
        var machine = CatStateMachine()
        XCTAssertFalse(machine.handle(.animationCompleted)); XCTAssertTrue(machine.handle(.pause)); XCTAssertEqual(machine.state, .paused)
        XCTAssertTrue(machine.handle(.resume)); XCTAssertEqual(machine.state, .sleeping)
    }
}
