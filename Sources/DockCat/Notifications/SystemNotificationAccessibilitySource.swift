import ApplicationServices
import DockCatCore
import OSLog

@MainActor final class SystemNotificationAccessibilitySource: SystemNotificationSourceControlling {
    enum Outcome: Equatable { case active, degraded, unavailable, permissionRequired }
    static let structuralNotifications = [
        kAXCreatedNotification as String, kAXChildrenChangedNotification as String,
        kAXLayoutChangedNotification as String, kAXWindowCreatedNotification as String,
        kAXValueChangedNotification as String, kAXUIElementDestroyedNotification as String
    ]
    private let trust: AccessibilityTrustChecking
    private let resolver: NotificationCenterProcessResolving
    private let client: AccessibilityAPIClientProtocol
    private let logger = Logger(subsystem: "com.example.DockCat", category: "AccessibilityObserver")
    private let eventHandler: @MainActor (NotificationSourceEvent) -> Void
    private let outcomeHandler: @MainActor (Outcome) -> Void
    private var observer: (any AccessibilityObserverReference)?
    private var application: (any AccessibilityElementReference)?
    private var registrations = Set<String>()
    private var process: NotificationCenterProcess?
    private var pendingSnapshot: Task<Void, Never>?
    private var sequence: UInt64 = 0
    private var started = false

    init(trust: AccessibilityTrustChecking = AccessibilityTrustController(), resolver: NotificationCenterProcessResolving = NotificationCenterProcessResolver(),
         client: AccessibilityAPIClientProtocol = AccessibilityAPIClient(),
         eventHandler: @escaping @MainActor (NotificationSourceEvent) -> Void,
         outcomeHandler: @escaping @MainActor (Outcome) -> Void) {
        self.trust = trust; self.resolver = resolver; self.client = client
        self.eventHandler = eventHandler; self.outcomeHandler = outcomeHandler
    }
    func start() {
        guard !started else { return }; started = true
        logger.info("Accessibility source starting")
        guard trust.isTrusted() else { started = false; outcomeHandler(.permissionRequired); return }
        resolver.startMonitoring { [weak self] in self?.processChanged() }
        attachResolvedProcess()
    }
    func stop() { stop(report: false) }
    private func stop(report: Bool) {
        guard started || observer != nil else { return }; started = false; pendingSnapshot?.cancel(); pendingSnapshot = nil
        detachObserver(); resolver.stopMonitoring(); logger.info("Accessibility source stopped")
        if report { outcomeHandler(.permissionRequired) }
    }
    private func attachResolvedProcess() {
        guard started else { return }
        guard trust.isTrusted() else { stop(report: true); return }
        let resolution = resolver.resolve()
        let resolved: NotificationCenterProcess; let fallback: Bool
        switch resolution {
        case .resolved(let value): resolved = value; fallback = false
        case .degraded(let value): resolved = value; fallback = true
        case .unavailable: logger.info("Notification Center process unavailable"); detachObserver(); outcomeHandler(.unavailable); return
        }
        logger.info("Notification Center resolved pid=\(resolved.processIdentifier, privacy: .public), fallback=\(fallback, privacy: .public)")
        if process?.processIdentifier == resolved.processIdentifier, observer != nil { return }
        if let previous = process { logger.info("Notification Center PID changed \(previous.processIdentifier, privacy: .public) -> \(resolved.processIdentifier, privacy: .public)") }
        detachObserver(); process = resolved
        let app = client.application(processIdentifier: resolved.processIdentifier)
        do {
            let made = try client.makeObserver(processIdentifier: resolved.processIdentifier) { [weak self] element, notification in
                self?.observed(element, notification: notification)
            }
            application = app; observer = made; client.attach(made)
            for notification in Self.structuralNotifications where !registrations.contains(notification) {
                do { try client.add(notification: notification, element: app, observer: made); registrations.insert(notification); logger.info("Registered AX signal \(notification, privacy: .public)") }
                catch { logger.info("AX registration failed category=\(String(describing: error), privacy: .public), signal=\(notification, privacy: .public)") }
            }
            if registrations.isEmpty { detachObserver(); outcomeHandler(.unavailable) }
            else if fallback || registrations.count < Self.structuralNotifications.count { outcomeHandler(.degraded) }
            else { outcomeHandler(.active) }
        } catch { logger.error("AX observer creation failed category=\(String(describing: error), privacy: .public)"); detachObserver(); outcomeHandler(.unavailable) }
    }
    private func detachObserver() {
        pendingSnapshot?.cancel(); pendingSnapshot = nil
        if let observer, let application { for notification in registrations { client.remove(notification: notification, element: application, observer: observer) }; client.detach(observer) }
        registrations.removeAll(); observer = nil; application = nil; process = nil
    }
    private func processChanged() { guard started else { return }; logger.info("Notification Center lifecycle event; resolving again"); attachResolvedProcess() }
    private func observed(_ changed: any AccessibilityElementReference, notification: String) {
        guard started else { return }; guard trust.isTrusted() else { stop(report: true); return }
        pendingSnapshot?.cancel()
        pendingSnapshot = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40)); guard !Task.isCancelled, let self, let process else { return }
            let candidate = (try? client.element(.parent, of: changed)) ?? changed
            sequence &+= 1
            let kind = Self.kind(notification)
            let result = AccessibilitySnapshotBuilder(client: client).build(from: candidate,
                origin: .init(bundleIdentifier: process.bundleIdentifier, processIdentifier: process.processIdentifier), kind: kind, sequence: sequence)
            logger.info("AX candidate snapshot count=\(self.sequence, privacy: .public), truncations=\(result.truncatedNodeCount, privacy: .public)")
            eventHandler(.accessibilitySnapshot(result.snapshot))
            pendingSnapshot = nil
        }
    }
    private static func kind(_ name: String) -> AccessibilityNotificationSnapshot.ObservationKind {
        switch name { case kAXCreatedNotification as String: .created; case kAXChildrenChangedNotification as String: .childrenChanged
        case kAXLayoutChangedNotification as String: .layoutChanged; case kAXWindowCreatedNotification as String: .windowCreated
        case kAXValueChangedNotification as String: .valueChanged; case kAXUIElementDestroyedNotification as String: .destroyed; default: .unknown }
    }
}
