import XCTest
@testable import DockCatCore

final class PlacementRefreshPolicyTests: XCTestCase {
    func testStableStateMappingIsExhaustive() {
        assertPlacement(.home, state: .sleeping)
        assertPlacement(.home, state: .waking, phase: .waking, active: true)
        assertPlacement(.home, state: .pickingUpCard, phase: .pickingUp, active: true)
        assertPlacement(.travellingToPresentation, state: .walkingToPresentation, phase: .travellingToPresentation, active: true)
        assertPlacement(.presentation, state: .presenting, phase: .presentingCard, active: true)
        assertPlacement(.presentation, state: .waitingForDismissal, phase: .waitingForDismissal)
        assertPlacement(.presentation, state: .preparingNextNotification, phase: .replacingCard, active: true)
        assertPlacement(.presentation, state: .dismissingCard, phase: .dismissingCard, active: true)
        assertPlacement(.travellingHome, state: .walkingHome, phase: .travellingHome, active: true)
        assertPlacement(.home, state: .settlingDown, phase: .settling, active: true)
    }

    func testPausedStateUsesOutboundTravelPhase() {
        assertPlacement(.travellingToPresentation, state: .paused, phase: .travellingToPresentation, active: true)
    }

    func testPausedStateUsesPresentationAndReturnPhases() {
        assertPlacement(.presentation, state: .paused, phase: .waitingForDismissal)
        assertPlacement(.presentation, state: .paused, phase: .dismissingCard, active: true)
        assertPlacement(.travellingHome, state: .paused, phase: .travellingHome, active: true)
    }

    func testPausedWithoutSessionIsHome() {
        assertPlacement(.home, state: .paused)
    }

    func testRecoveryAndDisablePreserveRecoveryVisuals() {
        XCTAssertEqual(resolve(state: .walkingToPresentation, phase: .travellingToPresentation, active: true, recovering: true), .hiddenOrRecovering)
        XCTAssertEqual(resolve(state: .waitingForDismissal, phase: .waitingForDismissal, enabled: false), .hiddenOrRecovering)
    }

    func testPolicySelectsStateSpecificVisibleResponse() {
        XCTAssertEqual(PlacementRefreshPolicy.action(for: .home), .moveToHome)
        XCTAssertEqual(PlacementRefreshPolicy.action(for: .travellingToPresentation), .retargetPresentationTravel)
        XCTAssertEqual(PlacementRefreshPolicy.action(for: .presentation), .moveToPresentation)
        XCTAssertEqual(PlacementRefreshPolicy.action(for: .travellingHome), .retargetHomeTravel)
        XCTAssertEqual(PlacementRefreshPolicy.action(for: .hiddenOrRecovering), .preserveRecoveryVisuals)
    }

    func testSpecificDisplayRestorationRequiresActualSleepingState() {
        for state in CatState.allCases {
            XCTAssertEqual(
                PlacementRefreshPolicy.canRestoreSpecificDisplay(catState: state),
                state == .sleeping,
                "Unexpected restoration boundary for \(state)"
            )
        }
    }

    func testMissingScreenRetainsLastValidPlacement() {
        XCTAssertEqual(
            PlacementRefreshPolicy.availabilityAction(
                hasResolvedPlacement: false, hasLastValidPlacement: true
            ),
            .retainLastValidPlacement
        )
        XCTAssertEqual(
            PlacementRefreshPolicy.availabilityAction(
                hasResolvedPlacement: false, hasLastValidPlacement: false
            ),
            .awaitFirstValidPlacement
        )
        XCTAssertEqual(
            PlacementRefreshPolicy.availabilityAction(
                hasResolvedPlacement: true, hasLastValidPlacement: true
            ),
            .applyResolvedPlacement
        )
    }

    private func assertPlacement(
        _ expected: CatLogicalPlacement,
        state: CatState,
        phase: PresentationPhase? = nil,
        active: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(resolve(state: state, phase: phase, active: active), expected, file: file, line: line)
    }

    private func resolve(
        state: CatState,
        phase: PresentationPhase? = nil,
        active: Bool = false,
        recovering: Bool = false,
        enabled: Bool = true
    ) -> CatLogicalPlacement {
        CatLogicalPlacementResolver.resolve(
            catState: state,
            presentationPhase: phase,
            hasChoreographyTask: active,
            isRecovering: recovering,
            isEnabled: enabled
        )
    }
}
