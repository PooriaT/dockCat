import XCTest
@testable import DockCatCore

final class CatTransitionTableTests: XCTestCase {
    private struct Pair: Hashable {
        let state: CatState
        let event: CatEvent
    }

    private let expected: [Pair: (CatState, CatCoordinatorEffect)] = [
        .init(state: .sleeping, event: .notificationAvailable): (.waking, .wake),
        .init(state: .waking, event: .animationCompleted): (.pickingUpCard, .pickUpCard),
        .init(state: .pickingUpCard, event: .animationCompleted): (.walkingToPresentation, .travelToPresentation),
        .init(state: .walkingToPresentation, event: .animationCompleted): (.presenting, .presentInitialCard),
        .init(state: .presenting, event: .cardPresented): (.waitingForDismissal, .enterWaitingState),
        .init(state: .waitingForDismissal, event: .notificationUpdated): (.presenting, .replaceActiveCard),
        .init(state: .waitingForDismissal, event: .transientExpired): (.preparingNextNotification, .selectNextQueueAction),
        .init(state: .waitingForDismissal, event: .userDismissed): (.preparingNextNotification, .selectNextQueueAction),
        .init(state: .waitingForDismissal, event: .sourceDisappeared): (.preparingNextNotification, .selectNextQueueAction),
        .init(state: .preparingNextNotification, event: .nextNotificationAvailable): (.presenting, .replaceActiveCard),
        .init(state: .preparingNextNotification, event: .queueEmpty): (.dismissingCard, .dismissExpandedCard),
        .init(state: .dismissingCard, event: .cardDismissed): (.walkingHome, .travelHome),
        .init(state: .walkingHome, event: .animationCompleted): (.settlingDown, .settleToSleep),
        .init(state: .settlingDown, event: .animationCompleted): (.sleeping, .none),
    ]

    func testCompleteStateEventMatrixHasExpectedDecisionAndEffect() {
        for state in CatState.allCases where state != .paused {
            for event in CatEvent.allCases {
                var machine = CatStateMachine(state: state)
                let result = machine.handle(event)

                if event == .pause {
                    assertTransition(result, previous: state, event: event, next: .paused, effect: .pauseVisualWork)
                } else if let (next, effect) = expected[.init(state: state, event: event)] {
                    assertTransition(result, previous: state, event: event, next: next, effect: effect)
                } else {
                    guard case .rejected = result else {
                        return XCTFail("Expected rejection for \(state) + \(event), got \(result)")
                    }
                    XCTAssertEqual(machine.state, state, "Rejected pair mutated state")
                    XCTAssertNil(result.transition, "Rejected pair exposed an executable effect")
                }
            }
        }
    }

    func testPausedMatrixAcceptsOnlyResumeWithRememberedState() {
        for event in CatEvent.allCases {
            var machine = CatStateMachine(state: .paused, stateBeforePause: .presenting)
            let result = machine.handle(event)
            if event == .resume {
                assertTransition(result, previous: .paused, event: .resume, next: .presenting, effect: .resumePriorWork)
            } else {
                guard case .rejected = result else { return XCTFail("Expected paused + \(event) rejection") }
                XCTAssertEqual(machine.state, .paused)
                XCTAssertNil(result.transition)
            }
        }
    }

    func testEveryAcceptedTransitionDefinesAnEffect() {
        let effects = Set(expected.values.map { $0.1 })
            .union([.pauseVisualWork, .resumePriorWork])
        XCTAssertTrue(effects.isSubset(of: Set(CatCoordinatorEffect.allCases)))
        XCTAssertTrue(expected.values.contains { $0.1 == .none })
    }

    private func assertTransition(
        _ result: CatTransitionResult,
        previous: CatState,
        event: CatEvent,
        next: CatState,
        effect: CatCoordinatorEffect,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .accepted(let transition) = result else {
            return XCTFail("Expected accepted transition, got \(result)", file: file, line: line)
        }
        XCTAssertEqual(transition.previousState, previous, file: file, line: line)
        XCTAssertEqual(transition.event, event, file: file, line: line)
        XCTAssertEqual(transition.nextState, next, file: file, line: line)
        XCTAssertEqual(transition.effect, effect, file: file, line: line)
    }
}
