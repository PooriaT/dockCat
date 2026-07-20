import DockCatCore
import OSLog
import Combine

@MainActor
protocol SystemNotificationSourceControlling: AnyObject {
    func start(generation: UInt64)
    func stop()
}

@MainActor
final class SystemNotificationAccessController: ObservableObject {
    @Published private(set) var health = SystemNotificationSourceHealth(.disabled)

    private let trust: AccessibilityTrustChecking
    private weak var source: SystemNotificationSourceControlling?
    private let logger = Logger(subsystem: DockCatProductIdentity.osLogSubsystem, category: "SystemNotificationSource")
    @Published private(set) var userRequested: Bool
    @Published private(set) var runtimeAllowed: Bool
    private(set) var generation: UInt64 = 0
    private var startRequested = false
    private var lastTrust: Bool?

    init(enabled: Bool, runtimeAllowed: Bool = true,
         trust: AccessibilityTrustChecking = AccessibilityTrustController(),
         source: SystemNotificationSourceControlling? = nil, startImmediately: Bool = true) {
        self.userRequested = enabled
        self.runtimeAllowed = runtimeAllowed
        self.trust = trust
        self.source = source
        if startImmediately { refresh() }
    }

    func setEnabled(_ enabled: Bool) {
        guard userRequested != enabled else { refresh(); return }
        userRequested = enabled
        logger.info("Source \(enabled ? "enabled" : "disabled", privacy: .public)")
        refresh()
    }

    func setRuntimeAllowed(_ allowed: Bool) {
        guard runtimeAllowed != allowed else { refresh(); return }
        runtimeAllowed = allowed
        logger.info("Source runtimeAllowed=\(allowed, privacy: .public)")
        refresh()
    }

    /// Passive refresh: this API never supplies the Accessibility prompt option.
    func refresh() {
        guard userRequested else {
            stopSource()
            transition(to: .init(.disabled))
            return
        }
        guard runtimeAllowed else {
            stopSource()
            transition(to: .init(.disabled, reason: .globallyDisabled))
            return
        }
        let trusted = trust.isTrusted()
        if lastTrust != trusted { logger.info("Accessibility trust changed: \(trusted, privacy: .public)") }
        let wasTrusted = lastTrust
        lastTrust = trusted
        guard trusted else {
            stopSource()
            transition(to: .init(.permissionRequired, reason: wasTrusted == true ? .permissionRevoked : .permissionMissing))
            return
        }
        guard let source else {
            transition(to: .init(.unavailable, reason: .observerNotImplemented))
            return
        }
        guard !startRequested else { return }
        generation &+= 1
        startRequested = true
        transition(to: .init(.starting))
        logger.info("Source start requested generation=\(self.generation, privacy: .public)")
        source.start(generation: generation)
    }

    /// The only path that invokes the prompting system API.
    func requestPermission() {
        guard userRequested else { return }
        logger.info("Accessibility permission request initiated")
        _ = trust.requestTrust()
        refresh()
    }

    func sourceDidStart() { guard acceptsSourceCallback else { return }; transition(to: .init(.active)) }
    func sourceDidDegrade() { guard acceptsSourceCallback else { return }; transition(to: .init(.degraded, reason: .compatibilityProblem)) }
    /// Reports a recoverable outage without stopping the source's process monitor.
    func sourceDidBecomeUnavailable() {
        guard acceptsSourceCallback else { return }
        transition(to: .init(.unavailable, reason: .processUnavailable))
    }
    func sourceDidFailToStart() {
        guard acceptsSourceCallback else { return }
        stopSource()
        transition(to: .init(.unavailable, reason: .startupFailed))
    }
    func sourceDidLosePermission() {
        guard acceptsSourceCallback else { return }
        lastTrust = false
        stopSource()
        transition(to: .init(.permissionRequired, reason: .permissionRevoked))
    }
    func shutdown() { stopSource() }

    func acceptsCallback(generation: UInt64) -> Bool {
        acceptsSourceCallback && generation == self.generation
    }

    private func stopSource() {
        guard startRequested else { return }
        startRequested = false
        generation &+= 1
        logger.info("Source stop requested generation=\(self.generation, privacy: .public)")
        source?.stop()
    }

    /// Reject callbacks from a source generation that has already been stopped.
    private var acceptsSourceCallback: Bool {
        userRequested && runtimeAllowed && lastTrust == true && startRequested
    }

    private func transition(to newHealth: SystemNotificationSourceHealth) {
        guard health != newHealth else { return }
        logger.info("Health transition: \(self.health.state.rawValue, privacy: .public) -> \(newHealth.state.rawValue, privacy: .public)")
        health = newHealth
    }
}
