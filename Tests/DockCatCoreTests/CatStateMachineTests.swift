import XCTest
@testable import DockCatCore

final class CatStateMachineTests: XCTestCase {
    func testFullTransientFlow() {
        var machine = CatStateMachine()
        let events: [CatEvent] = [.notificationAvailable, .animationCompleted, .animationCompleted, .animationCompleted, .cardPresented, .transientExpired, .queueEmpty, .animationCompleted, .animationCompleted]
        for event in events { XCTAssertTrue(machine.handle(event), "Rejected \(event) from \(machine.state)") }
        XCTAssertEqual(machine.state, .sleeping)
    }
    func testQueuedAndPersistentFlow() {
        var machine = CatStateMachine()
        [.notificationAvailable, .animationCompleted, .animationCompleted, .animationCompleted, .cardPresented, .userDismissed, .nextNotificationAvailable, .cardPresented].forEach { XCTAssertTrue(machine.handle($0)) }
        XCTAssertEqual(machine.state, .waitingForDismissal)
    }
    func testInvalidTransitionAndPauseResume() {
        var machine = CatStateMachine()
        XCTAssertFalse(machine.handle(.animationCompleted)); XCTAssertTrue(machine.handle(.pause)); XCTAssertEqual(machine.state, .paused)
        XCTAssertTrue(machine.handle(.resume)); XCTAssertEqual(machine.state, .sleeping)
    }
}
