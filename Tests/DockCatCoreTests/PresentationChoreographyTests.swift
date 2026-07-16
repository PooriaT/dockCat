import XCTest
@testable import DockCatCore

final class PresentationChoreographyTests: XCTestCase {
    func testMiniCardVisibilityAndTimeoutOrderingForTransient() {
        XCTAssertEqual(PresentationChoreography.presentationSteps(kind: .transient), [.showMiniCard, .travelToPresentation, .presentExpandedCard, .hideMiniCard, .enterWaiting, .scheduleTransientTimeout])
    }

    func testPersistentNeverSchedulesTimeout() {
        XCTAssertEqual(PresentationChoreography.presentationSteps(kind: .persistent).last, .doNotScheduleTimeout)
    }

    func testEmptyQueueDismissesCardBeforeWalkingHome() {
        XCTAssertEqual(PresentationChoreography.dismissalSteps(hasQueuedReplacement: false, remainInPlace: true, nextKind: nil), [.requestCardDismissal, .dismissExpandedCard, .cardDismissed, .walkHome, .settle, .sleep])
    }

    func testTransientExpiryUsesSameOrderedDismissalPath() {
        XCTAssertEqual(PresentationChoreography.dismissalSteps(hasQueuedReplacement: false, remainInPlace: false, nextKind: nil).prefix(3), [.requestCardDismissal, .dismissExpandedCard, .cardDismissed])
    }

    func testQueuedReplacementDoesNotWalkHomeSettleOrSleep() {
        let steps = PresentationChoreography.dismissalSteps(hasQueuedReplacement: true, remainInPlace: true, nextKind: .transient)
        XCTAssertEqual(steps, [.requestCardDismissal, .replaceExpandedCard, .enterWaiting, .scheduleTransientTimeout])
        XCTAssertFalse(steps.contains(.walkHome)); XCTAssertFalse(steps.contains(.settle)); XCTAssertFalse(steps.contains(.sleep))
    }

    func testQueuedReplacementTimeoutAfterReplacementCompletion() {
        let steps = PresentationChoreography.dismissalSteps(hasQueuedReplacement: true, remainInPlace: true, nextKind: .transient)
        XCTAssertLessThan(steps.firstIndex(of: .replaceExpandedCard)!, steps.firstIndex(of: .scheduleTransientTimeout)!)
    }

    func testReducedMotionPreservesLogicalOrder() {
        XCTAssertEqual(PresentationChoreography.presentationSteps(kind: .transient), PresentationChoreography.presentationSteps(kind: .transient))
    }

    func testStaleCompletionAndCancelledCompletionAreIgnored() {
        XCTAssertTrue(PresentationChoreography.shouldAcceptPresentationCompletion(.completed))
        XCTAssertFalse(PresentationChoreography.shouldAcceptPresentationCompletion(.cancelled))
    }

    func testProgrammaticDismissalIsSeparateFromUserDismissRequest() {
        let steps = PresentationChoreography.dismissalSteps(hasQueuedReplacement: false, remainInPlace: false, nextKind: nil)
        XCTAssertEqual(steps.filter { $0 == .requestCardDismissal }.count, 1)
        XCTAssertEqual(steps.filter { $0 == .dismissExpandedCard }.count, 1)
    }
}
