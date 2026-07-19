import XCTest
@testable import DockCatCore

final class DockCatRuntimeLifecycleTests: XCTestCase {
    private func lifecycle(enabled: Bool = true) -> DockCatRuntimeLifecycle {
        .init(initiallyEnabled: enabled, visualMode: .full, systemSourceRequested: true)
    }

    func testStartupIntentReflectsSavedEnablement() {
        XCTAssertEqual(lifecycle().snapshot.mode, .enabling)
        XCTAssertEqual(lifecycle(enabled: false).snapshot.mode, .disabled)
    }

    func testEnabledPauseResumeLifecycle() {
        var value = lifecycle()
        XCTAssertNotNil(value.apply(.finishEnabling).transition)
        XCTAssertEqual(value.apply(.pauseDelivery).transition?.next.mode, .deliveryPaused)
        XCTAssertEqual(value.apply(.resumeDelivery).transition?.next.mode, .running)
    }

    func testDisableAndReEnableUseExplicitIntermediateStates() {
        var value = lifecycle()
        _ = value.apply(.finishEnabling)
        XCTAssertEqual(value.apply(.beginDisabling).transition?.next.mode, .disabling)
        XCTAssertEqual(value.apply(.finishDisabling).transition?.next.mode, .disabled)
        XCTAssertEqual(value.apply(.beginEnabling).transition?.next.mode, .enabling)
        XCTAssertEqual(value.apply(.finishEnabling).transition?.next.mode, .running)
    }

    func testPauseWhileDisabledIsRejectedAndDisableWhilePausedWins() {
        var disabled = lifecycle(enabled: false)
        guard case .rejected(let rejection) = disabled.apply(.pauseDelivery) else {
            return XCTFail("Pause should be rejected")
        }
        XCTAssertEqual(rejection.reason, .invalidTransition)

        var paused = lifecycle()
        _ = paused.apply(.finishEnabling)
        _ = paused.apply(.pauseDelivery)
        XCTAssertEqual(paused.apply(.beginDisabling).transition?.next.mode, .disabling)
    }

    func testShutdownOverridesEveryModeAndIsTerminal() {
        for mode in DockCatRuntimeMode.allCases where mode != .shuttingDown {
            var value = lifecycle(enabled: false)
            switch mode {
            case .disabled: break
            case .enabling: _ = value.apply(.beginEnabling)
            case .running: _ = value.apply(.beginEnabling); _ = value.apply(.finishEnabling)
            case .deliveryPaused:
                _ = value.apply(.beginEnabling); _ = value.apply(.finishEnabling); _ = value.apply(.pauseDelivery)
            case .disabling:
                _ = value.apply(.beginEnabling); _ = value.apply(.finishEnabling); _ = value.apply(.beginDisabling)
            case .shuttingDown: break
            }
            XCTAssertEqual(value.apply(.shutdown).transition?.next.mode, .shuttingDown)
            guard case .rejected(let rejection) = value.apply(.beginEnabling) else {
                return XCTFail("Shutdown must be terminal")
            }
            XCTAssertEqual(rejection.reason, .shutdownIsTerminal)
        }
    }

    func testVisualModeIsOrthogonalAndSourceGateFollowsRuntime() {
        var value = lifecycle()
        _ = value.apply(.updateVisualMode(.animationsPaused))
        XCTAssertEqual(value.snapshot.mode, .enabling)
        XCTAssertEqual(value.snapshot.visualMode, .animationsPaused)
        XCTAssertFalse(value.snapshot.systemSourceRuntimeAllowed)
        _ = value.apply(.finishEnabling)
        XCTAssertTrue(value.snapshot.systemSourceRuntimeAllowed)
        _ = value.apply(.pauseDelivery)
        XCTAssertTrue(value.snapshot.systemSourceRuntimeAllowed)
        XCTAssertEqual(value.snapshot.visualMode, .animationsPaused)
    }
}
