import XCTest
@testable import DockCat

@MainActor final class SystemNotificationAccessibilitySourceTests: XCTestCase {
    func testUntrustedRegistersNothing() {
        let api = SourceAXFake(), trust = SourceTrustFake(false), resolver = ResolverFake(.resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 1, localizedName: nil)))
        var outcomes: [SystemNotificationAccessibilitySource.Outcome] = []
        let source = make(trust, resolver, api) { outcomes.append($0) }
        source.start()
        XCTAssertEqual(api.adds, 0); XCTAssertEqual(outcomes.last, .permissionRequired)
    }
    func testStartStopAreIdempotentAndFullRegistrationIsActive() {
        let api = SourceAXFake(), resolver = ResolverFake(.resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 1, localizedName: nil)))
        var outcomes: [SystemNotificationAccessibilitySource.Outcome] = []
        let source = make(SourceTrustFake(true), resolver, api) { outcomes.append($0) }
        source.start(); source.start(); XCTAssertEqual(api.observers, 1); XCTAssertEqual(outcomes.last, .active)
        source.stop(); source.stop(); XCTAssertEqual(api.detaches, 1); XCTAssertEqual(api.removes, SystemNotificationAccessibilitySource.structuralNotifications.count)
    }
    func testPartialAndNoRegistrationAreTruthful() {
        let process = NotificationCenterResolution.resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 1, localizedName: nil))
        var outcome: SystemNotificationAccessibilitySource.Outcome?
        let partial = SourceAXFake(); partial.failAfter = 1
        let partialSource = make(SourceTrustFake(true), ResolverFake(process), partial) { outcome = $0 }; partialSource.start()
        XCTAssertEqual(outcome, .degraded)
        let none = SourceAXFake(); none.failAfter = 0
        let noneSource = make(SourceTrustFake(true), ResolverFake(process), none) { outcome = $0 }; noneSource.start()
        XCTAssertEqual(outcome, .unavailable)
    }
    func testPIDReplacementDetachesAndReattaches() {
        let api = SourceAXFake(), resolver = ResolverFake(.resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 1, localizedName: nil)))
        let source = make(SourceTrustFake(true), resolver, api) { _ in }; source.start()
        resolver.resolution = .resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 2, localizedName: nil)); resolver.changed?()
        XCTAssertEqual(api.observers, 2); XCTAssertEqual(api.detaches, 1)
    }
    func testUnavailableDuringRestartKeepsLaunchMonitorActive() {
        let api = SourceAXFake(), resolver = ResolverFake(.resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 1, localizedName: nil)))
        var outcomes: [SystemNotificationAccessibilitySource.Outcome] = []
        let source = make(SourceTrustFake(true), resolver, api) { outcomes.append($0) }
        source.start()

        resolver.resolution = .unavailable; resolver.changed?()
        XCTAssertEqual(outcomes.last, .unavailable)
        XCTAssertNotNil(resolver.changed)

        resolver.resolution = .resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 2, localizedName: nil)); resolver.changed?()
        XCTAssertEqual(outcomes.last, .active)
        XCTAssertEqual(api.observers, 2)
    }
    func testDistinctElementsAreCoalescedIndependently() async {
        let api = SourceAXFake(), resolver = ResolverFake(.resolved(.init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 1, localizedName: nil)))
        var snapshots = 0
        let source = SystemNotificationAccessibilitySource(
            trust: SourceTrustFake(true), resolver: resolver, client: api,
            eventHandler: { _ in snapshots += 1 }, outcomeHandler: { _ in }
        )
        source.start()

        api.callback?(SourceElement(101), "AXCreated")
        api.callback?(SourceElement(202), "AXCreated")
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(snapshots, 2)
    }
    private func make(_ trust: SourceTrustFake, _ resolver: ResolverFake, _ api: SourceAXFake,
                      outcome: @escaping @MainActor @Sendable (SystemNotificationAccessibilitySource.Outcome) -> Void) -> SystemNotificationAccessibilitySource {
        .init(trust: trust, resolver: resolver, client: api, eventHandler: { _ in }, outcomeHandler: outcome)
    }
}

@MainActor private final class SourceTrustFake: AccessibilityTrustChecking {
    var trusted: Bool; init(_ trusted: Bool) { self.trusted = trusted }
    func isTrusted() -> Bool { trusted }; func requestTrust() -> Bool { trusted }
}
@MainActor private final class ResolverFake: NotificationCenterProcessResolving {
    var resolution: NotificationCenterResolution
    var changed: (@MainActor @Sendable () -> Void)?
    init(_ resolution: NotificationCenterResolution) { self.resolution = resolution }
    func resolve() -> NotificationCenterResolution { resolution }
    func startMonitoring(_ changed: @escaping @MainActor @Sendable () -> Void) { self.changed = changed }
    func stopMonitoring() { changed = nil }
}
@MainActor private final class SourceElement: AccessibilityElementReference { let traversalIdentifier: Int; init(_ id: Int) { traversalIdentifier = id } }
@MainActor private final class SourceObserver: AccessibilityObserverReference {}
@MainActor private final class SourceAXFake: AccessibilityAPIClientProtocol {
    var adds = 0, removes = 0, observers = 0, detaches = 0; var failAfter: Int?
    var callback: ((any AccessibilityElementReference, String) -> Void)?
    func application(processIdentifier: pid_t) -> any AccessibilityElementReference { SourceElement(Int(processIdentifier)) }
    func makeObserver(processIdentifier: pid_t, callback: @escaping (any AccessibilityElementReference, String) -> Void) throws -> any AccessibilityObserverReference { observers += 1; self.callback = callback; return SourceObserver() }
    func attach(_ observer: any AccessibilityObserverReference) {}
    func detach(_ observer: any AccessibilityObserverReference) { detaches += 1 }
    func add(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) throws {
        if let failAfter, adds >= failAfter { throw AccessibilityClientError.unsupported }; adds += 1
    }
    func remove(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) { removes += 1 }
    func string(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> String? { nil }
    func boolean(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> Bool? { nil }
    func elements(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> [any AccessibilityElementReference] { [] }
    func element(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> (any AccessibilityElementReference)? { nil }
    func actions(of element: any AccessibilityElementReference) throws -> [String] { [] }
}
