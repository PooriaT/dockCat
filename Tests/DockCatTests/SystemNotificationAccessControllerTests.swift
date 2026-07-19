import XCTest
@testable import DockCat

@MainActor final class SystemNotificationAccessControllerTests: XCTestCase {
    func testDisabledNeverChecksOrPrompts() {
        let trust = TrustFake(true)
        let controller = SystemNotificationAccessController(enabled: false, trust: trust)
        controller.refresh()
        XCTAssertEqual(controller.health.state, .disabled)
        XCTAssertEqual(trust.checks, 0); XCTAssertEqual(trust.requests, 0)
    }

    func testPassiveRefreshDoesNotPromptAndExplicitActionDoes() {
        let trust = TrustFake(false)
        let controller = SystemNotificationAccessController(enabled: true, trust: trust)
        controller.refresh()
        XCTAssertGreaterThan(trust.checks, 0); XCTAssertEqual(trust.requests, 0)
        XCTAssertEqual(controller.health.state, .permissionRequired)
        controller.requestPermission()
        XCTAssertEqual(trust.requests, 1)
    }

    func testTrustedWithoutObserverIsUnavailableNotActive() {
        let controller = SystemNotificationAccessController(enabled: true, trust: TrustFake(true))
        XCTAssertEqual(controller.health, .init(.unavailable, reason: .observerNotImplemented))
    }

    func testSourceMustReportSuccessAndRefreshDoesNotDuplicateStart() {
        let source = SourceFake()
        let controller = SystemNotificationAccessController(enabled: true, trust: TrustFake(true), source: source)
        XCTAssertEqual(controller.health.state, .starting); XCTAssertEqual(source.starts, 1)
        controller.refresh(); XCTAssertEqual(source.starts, 1); XCTAssertNotEqual(controller.health.state, .active)
        controller.sourceDidStart(); XCTAssertEqual(controller.health.state, .active)
    }

    func testRevocationAndDisableStopIdempotently() {
        let trust = TrustFake(true); let source = SourceFake()
        let controller = SystemNotificationAccessController(enabled: true, trust: trust, source: source)
        controller.sourceDidStart(); trust.trusted = false; controller.refresh()
        XCTAssertEqual(controller.health.reason, .permissionRevoked); XCTAssertEqual(source.stops, 1)
        controller.refresh(); XCTAssertEqual(source.stops, 1)
        controller.setEnabled(false); XCTAssertEqual(controller.health.state, .disabled)
    }

    func testTypedReportsMapToDegradedAndUnavailable() {
        let source = SourceFake()
        let controller = SystemNotificationAccessController(enabled: true, trust: TrustFake(true), source: source)
        controller.sourceDidDegrade(); XCTAssertEqual(controller.health, .init(.degraded, reason: .compatibilityProblem))
        controller.sourceDidFailToStart(); XCTAssertEqual(controller.health, .init(.unavailable, reason: .startupFailed))
        XCTAssertEqual(source.stops, 1)
        controller.refresh()
        XCTAssertEqual(source.starts, 2)
        XCTAssertEqual(controller.health.state, .starting)
    }

    func testRecoverableUnavailableKeepsSourceRunning() {
        let source = SourceFake()
        let controller = SystemNotificationAccessController(enabled: true, trust: TrustFake(true), source: source)

        controller.sourceDidBecomeUnavailable()

        XCTAssertEqual(controller.health, .init(.unavailable, reason: .processUnavailable))
        XCTAssertEqual(source.stops, 0)
        controller.sourceDidStart()
        XCTAssertEqual(controller.health.state, .active)
        XCTAssertEqual(source.starts, 1)
    }

    func testDeferredStartupCanInstallSynchronousOutcomeHandlerFirst() {
        let source = SourceFake()
        let controller = SystemNotificationAccessController(
            enabled: true, trust: TrustFake(true), source: source, startImmediately: false
        )
        XCTAssertEqual(controller.health.state, .disabled)
        XCTAssertEqual(source.starts, 0)

        source.onStart = { [weak controller] in controller?.sourceDidStart() }
        controller.refresh()

        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(controller.health.state, .active)
    }

    func testCallbacksAfterDisableCannotOverwriteDisabledHealth() {
        let source = SourceFake()
        let controller = SystemNotificationAccessController(enabled: true, trust: TrustFake(true), source: source)
        controller.setEnabled(false)

        controller.sourceDidFailToStart()
        controller.sourceDidLosePermission()
        controller.sourceDidDegrade()
        controller.sourceDidStart()

        XCTAssertEqual(controller.health.state, .disabled)
        XCTAssertEqual(source.stops, 1)
    }

    func testRuntimeGateStopsWithoutChangingUserPreferenceAndRestartsWithGeneration() {
        let source = SourceFake()
        let controller = SystemNotificationAccessController(
            enabled: true, runtimeAllowed: false, trust: TrustFake(true), source: source
        )
        XCTAssertTrue(controller.userRequested)
        XCTAssertEqual(controller.health.reason, .globallyDisabled)
        XCTAssertEqual(source.starts, 0)

        controller.setRuntimeAllowed(true)
        let firstGeneration = source.generations.last
        XCTAssertEqual(source.starts, 1)
        XCTAssertEqual(firstGeneration, controller.generation)
        controller.setRuntimeAllowed(false)
        XCTAssertEqual(source.stops, 1)
        XCTAssertTrue(controller.userRequested)
        XCTAssertEqual(controller.health.reason, .globallyDisabled)
        XCTAssertFalse(controller.acceptsCallback(generation: firstGeneration!))

        controller.setRuntimeAllowed(true)
        XCTAssertEqual(source.starts, 2)
        XCTAssertGreaterThan(source.generations.last!, firstGeneration!)
    }

    func testDelayedStartupFailureCannotOverwritePermissionRevocation() {
        let trust = TrustFake(true)
        let source = SourceFake()
        let controller = SystemNotificationAccessController(enabled: true, trust: trust, source: source)
        trust.trusted = false
        controller.refresh()

        controller.sourceDidFailToStart()

        XCTAssertEqual(controller.health, .init(.permissionRequired, reason: .permissionRevoked))
        XCTAssertEqual(source.stops, 1)
    }
}

@MainActor private final class TrustFake: AccessibilityTrustChecking {
    var trusted: Bool; var checks = 0; var requests = 0
    init(_ trusted: Bool) { self.trusted = trusted }
    func isTrusted() -> Bool { checks += 1; return trusted }
    func requestTrust() -> Bool { requests += 1; return trusted }
}
@MainActor private final class SourceFake: SystemNotificationSourceControlling {
    var starts = 0; var stops = 0; var generations: [UInt64] = []; var onStart: (() -> Void)?
    func start(generation: UInt64) { starts += 1; generations.append(generation); onStart?() }
    func stop() { stops += 1 }
}
