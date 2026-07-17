import XCTest
@testable import DockCatCore

final class CatEffectChainTests: XCTestCase {
    func testRejectedTransitionExecutesZeroEffects() {
        var machine = CatStateMachine()
        let result = machine.handle(.cardPresented)
        XCTAssertNil(CatEffectChainPolicy.effect(for: result))
    }

    func testSuccessfulEffectCompletionSubmitsExpectedNextEvent() {
        XCTAssertEqual(
            CatEffectChainPolicy.action(after: .completed(nextEvent: .animationCompleted)),
            .submit(.animationCompleted)
        )
    }

    func testEffectCancellationAndFailureNeverSubmitLaterEffects() {
        XCTAssertEqual(CatEffectChainPolicy.action(after: .cancelled), .stop)
        XCTAssertEqual(CatEffectChainPolicy.action(after: .failed), .recover)
    }

    func testImpossibleSequenceRequestsRecoveryOnceUntilCompletion() {
        var gate = CatRecoveryGate()
        XCTAssertTrue(gate.requestRecovery())
        XCTAssertFalse(gate.requestRecovery())
        gate.recoveryCompleted()
        XCTAssertTrue(gate.requestRecovery())
    }
}
