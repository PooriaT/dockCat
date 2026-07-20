import DockCatCore
import XCTest

final class CardInteractionStateTests: XCTestCase {
    private let firstID = PresentationSessionID(
        generation: 1, notificationID: UUID()
    )

    func testNewPresentationStartsPassive() {
        var state = CardInteractionState()
        state.beginPresentation(firstID)

        XCTAssertEqual(state.mode, .passive)
        XCTAssertEqual(state.presentationSessionID, firstID)
        XCTAssertEqual(state.latestInteractionGeneration, 0)
    }

    func testEveryExplicitTriggerEntersInteractiveMode() {
        for trigger in [
            CardInteractionTrigger.pointer,
            .keyboardNavigation,
            .accessibility
        ] {
            var state = CardInteractionState()
            state.beginPresentation(firstID)

            let result = state.requestInteraction(
                for: firstID,
                trigger: trigger,
                previousApplication: .init(processIdentifier: 42),
                dockCatBecameActive: true
            )

            guard case .entered(let session) = result else {
                return XCTFail("Expected an entered result for \(trigger)")
            }
            XCTAssertEqual(session.trigger, trigger)
            XCTAssertEqual(session.generation, 1)
            XCTAssertEqual(state.mode, .interactive(session))
        }
    }

    func testRepeatedRequestIsIdempotentAndPreservesRestorationTarget() {
        var state = CardInteractionState()
        state.beginPresentation(firstID)
        let first = state.requestInteraction(
            for: firstID,
            trigger: .pointer,
            previousApplication: .init(processIdentifier: 42),
            dockCatBecameActive: true
        )
        let repeated = state.requestInteraction(
            for: firstID,
            trigger: .accessibility,
            previousApplication: .init(processIdentifier: 99),
            dockCatBecameActive: false
        )

        guard case .entered(let entered) = first,
              case .unchanged(let unchanged) = repeated else {
            return XCTFail("Expected entered then unchanged")
        }
        XCTAssertEqual(unchanged, entered)
        XCTAssertEqual(unchanged.previousApplication?.processIdentifier, 42)
        XCTAssertEqual(state.latestInteractionGeneration, 1)
    }

    func testReplacementReturnsToPassiveAndRejectsOldPresentation() {
        var state = CardInteractionState()
        state.beginPresentation(firstID)
        _ = state.requestInteraction(
            for: firstID, trigger: .pointer,
            previousApplication: nil, dockCatBecameActive: true
        )
        let replacementID = PresentationSessionID(
            generation: 2, notificationID: UUID()
        )

        state.beginPresentation(replacementID)

        XCTAssertEqual(state.mode, .passive)
        XCTAssertEqual(
            state.requestInteraction(
                for: firstID, trigger: .pointer,
                previousApplication: nil, dockCatBecameActive: true
            ),
            .stalePresentation
        )
    }

    func testStaleInteractionGenerationCannotExitOrRestore() {
        var state = CardInteractionState()
        state.beginPresentation(firstID)
        _ = state.requestInteraction(
            for: firstID, trigger: .pointer,
            previousApplication: nil, dockCatBecameActive: true
        )

        XCTAssertEqual(
            state.exit(
                .close, for: firstID,
                expectedInteractionGeneration: 999
            ),
            .staleGeneration
        )
        XCTAssertFalse(state.isCurrent(
            interactionGeneration: 999,
            presentationSessionID: firstID
        ))
    }

    func testOpenAndCloseHaveDistinctRestorationPolicies() {
        XCTAssertEqual(CardInteractionExit.close.restorationPolicy, .restoreIfSafe)
        XCTAssertEqual(CardInteractionExit.openAction.restorationPolicy, .never)
    }

    func testInitialFocusOrderIsDeterministic() {
        XCTAssertEqual(CardInitialFocusTarget.resolve(
            hasOpenAction: true, canDismiss: true,
            bodySupportsKeyboardScrolling: true
        ), .open)
        XCTAssertEqual(CardInitialFocusTarget.resolve(
            hasOpenAction: false, canDismiss: true,
            bodySupportsKeyboardScrolling: true
        ), .close)
        XCTAssertEqual(CardInitialFocusTarget.resolve(
            hasOpenAction: false, canDismiss: false,
            bodySupportsKeyboardScrolling: true
        ), .message)
    }
}
