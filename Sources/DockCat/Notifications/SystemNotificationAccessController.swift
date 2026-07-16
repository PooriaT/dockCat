import DockCatCore
import OSLog
import Combine

@MainActor
protocol SystemNotificationSourceControlling: AnyObject {
    func start()
    func stop()
}

@MainActor
final class SystemNotificationAccessController: ObservableObject {
    @Published private(set) var health = SystemNotificationSourceHealth(.disabled)

    private let trust: AccessibilityTrustChecking
    private weak var source: SystemNotificationSourceControlling?
    private let logger = Logger(subsystem: "com.example.DockCat", category: "SystemNotificationSource")
    private var enabled: Bool
    private var startRequested = false
    private var lastTrust: Bool?

    init(enabled: Bool, trust: AccessibilityTrustChecking = AccessibilityTrustController(), source: SystemNotificationSourceControlling? = nil) {
        self.enabled = enabled
        self.trust = trust
        self.source = source
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { refresh(); return }
        self.enabled = enabled
        logger.info("Source \(enabled ? "enabled" : "disabled", privacy: .public)")
        refresh()
    }

    /// Passive refresh: this API never supplies the Accessibility prompt option.
    func refresh() {
        guard enabled else {
            stopSource()
            transition(to: .init(.disabled))
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
        startRequested = true
        transition(to: .init(.starting))
        logger.info("Source start requested")
        source.start()
    }

    /// The only path that invokes the prompting system API.
    func requestPermission() {
        guard enabled else { return }
        logger.info("Accessibility permission request initiated")
        _ = trust.requestTrust()
        refresh()
    }

    func sourceDidStart() { guard enabled, lastTrust == true, startRequested else { return }; transition(to: .init(.active)) }
    func sourceDidDegrade() { guard enabled else { return }; transition(to: .init(.degraded, reason: .compatibilityProblem)) }
    func sourceDidFailToStart() { startRequested = false; transition(to: .init(.unavailable, reason: .startupFailed)) }
    func sourceDidLosePermission() { lastTrust = false; stopSource(); transition(to: .init(.permissionRequired, reason: .permissionRevoked)) }
    func shutdown() { stopSource() }

    private func stopSource() {
        guard startRequested else { return }
        startRequested = false
        logger.info("Source stop requested")
        source?.stop()
    }

    private func transition(to newHealth: SystemNotificationSourceHealth) {
        guard health != newHealth else { return }
        logger.info("Health transition: \(self.health.state.rawValue, privacy: .public) -> \(newHealth.state.rawValue, privacy: .public)")
        health = newHealth
    }
}
