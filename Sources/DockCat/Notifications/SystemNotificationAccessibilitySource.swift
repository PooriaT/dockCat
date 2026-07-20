import ApplicationServices
import DockCatCore
import OSLog

@MainActor final class SystemNotificationAccessibilitySource: SystemNotificationSourceControlling {
    enum Outcome: Equatable { case active, degraded, unavailable, permissionRequired }
    private static let createdNotification = "AXCreated"
    private static let childrenChangedNotification = "AXChildrenChanged"
    private static let layoutChangedNotification = "AXLayoutChanged"
    private static let windowCreatedNotification = "AXWindowCreated"
    private static let valueChangedNotification = "AXValueChanged"
    private static let elementDestroyedNotification = "AXUIElementDestroyed"
    static let structuralNotifications = [
        createdNotification, childrenChangedNotification, layoutChangedNotification,
        windowCreatedNotification, valueChangedNotification, elementDestroyedNotification
    ]
    private let trust: AccessibilityTrustChecking
    private let resolver: NotificationCenterProcessResolving
    private let client: AccessibilityAPIClientProtocol
    private let dismissalRegistry: AccessibilityElementRegistry
    private let logger = Logger(subsystem: "com.example.DockCat", category: "AccessibilityObserver")
    private let eventHandler: @MainActor (NotificationSourceEvent, UInt64) -> Void
    private var outcomeHandler: @MainActor (Outcome) -> Void
    private var observer: (any AccessibilityObserverReference)?
    private var application: (any AccessibilityElementReference)?
    private var registrations = Set<String>()
    private var process: NotificationCenterProcess?
    private var pendingSnapshots: [Int: Task<Void, Never>] = [:]
    private var sequence: UInt64 = 0
    private var started = false
    private var generation: UInt64 = 0

    init(trust: AccessibilityTrustChecking = AccessibilityTrustController(), resolver: NotificationCenterProcessResolving = NotificationCenterProcessResolver(),
         client: AccessibilityAPIClientProtocol = AccessibilityAPIClient(),
         dismissalRegistry: AccessibilityElementRegistry = AccessibilityElementRegistry(),
         eventHandler: @escaping @MainActor (NotificationSourceEvent) -> Void,
         outcomeHandler: @escaping @MainActor (Outcome) -> Void) {
        self.trust = trust; self.resolver = resolver; self.client = client; self.dismissalRegistry = dismissalRegistry
        self.eventHandler = { event, _ in eventHandler(event) }; self.outcomeHandler = outcomeHandler
    }
    init(trust: AccessibilityTrustChecking = AccessibilityTrustController(), resolver: NotificationCenterProcessResolving = NotificationCenterProcessResolver(),
         client: AccessibilityAPIClientProtocol = AccessibilityAPIClient(),
         dismissalRegistry: AccessibilityElementRegistry = AccessibilityElementRegistry(),
         generatedEventHandler: @escaping @MainActor (NotificationSourceEvent, UInt64) -> Void,
         outcomeHandler: @escaping @MainActor (Outcome) -> Void) {
        self.trust = trust; self.resolver = resolver; self.client = client; self.dismissalRegistry = dismissalRegistry
        self.eventHandler = generatedEventHandler; self.outcomeHandler = outcomeHandler
    }
    func setOutcomeHandler(_ handler: @escaping @MainActor (Outcome) -> Void) { outcomeHandler = handler }
    func start() { start(generation: generation &+ 1) }
    func start(generation: UInt64) {
        guard !started else { return }; started = true; self.generation = generation
        logger.info("Accessibility source starting")
        guard trust.isTrusted() else { started = false; outcomeHandler(.permissionRequired); return }
        resolver.startMonitoring { [weak self] in self?.processChanged() }
        attachResolvedProcess()
    }
    func stop() { stop(report: false) }
    private func stop(report: Bool) {
        guard started || observer != nil else { return }; started = false; cancelPendingSnapshots()
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
        dismissalRegistry.removeAll()
        cancelPendingSnapshots()
        if let observer, let application { for notification in registrations { client.remove(notification: notification, element: application, observer: observer) }; client.detach(observer) }
        registrations.removeAll(); observer = nil; application = nil; process = nil
    }
    private func processChanged() { guard started else { return }; logger.info("Notification Center lifecycle event; resolving again"); attachResolvedProcess() }
    private func observed(_ changed: any AccessibilityElementReference, notification: String) {
        guard started else { return }; guard trust.isTrusted() else { stop(report: true); return }
        let ownedGeneration = generation
        let elementIdentifier = changed.traversalIdentifier
        pendingSnapshots[elementIdentifier]?.cancel()
        pendingSnapshots[elementIdentifier] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40)); guard !Task.isCancelled, let self,
                self.started, self.generation == ownedGeneration, let process else { return }
            let candidate = (try? client.element(.parent, of: changed)) ?? changed
            sequence &+= 1
            let kind = Self.kind(notification)
            let observedIdentifier = try? client.string(.identifier, of: changed)
            // A destroyed callback is normal after a successful close. Clearing is
            // conservative: it prevents retaining stale controls across lifecycle churn.
            let dismissalToken: AccessibilityDismissalToken?
            if kind == .destroyed { dismissalRegistry.removeAll(); dismissalToken = nil }
            else { dismissalToken = dismissalRegistry.register(root: candidate, processIdentifier: process.processIdentifier) }
            let result = AccessibilitySnapshotBuilder(client: client).build(from: candidate,
                origin: .init(bundleIdentifier: process.bundleIdentifier, processIdentifier: process.processIdentifier),
                kind: kind, sequence: sequence, observedElementIdentifier: observedIdentifier,
                opaqueDismissalTokenIdentifier: dismissalToken?.identifier)
            logger.info("AX candidate snapshot count=\(self.sequence, privacy: .public), truncations=\(result.truncatedNodeCount, privacy: .public)")
            eventHandler(.accessibilitySnapshot(result.snapshot), ownedGeneration)
            pendingSnapshots[elementIdentifier] = nil
        }
    }
    private func cancelPendingSnapshots() {
        pendingSnapshots.values.forEach { $0.cancel() }
        pendingSnapshots.removeAll(keepingCapacity: true)
    }
    private static func kind(_ name: String) -> AccessibilityNotificationSnapshot.ObservationKind {
        switch name {
        case createdNotification: .created
        case childrenChangedNotification: .childrenChanged
        case layoutChangedNotification: .layoutChanged
        case windowCreatedNotification: .windowCreated
        case valueChangedNotification: .valueChanged
        case elementDestroyedNotification: .destroyed
        default: .unknown
        }
    }
}
