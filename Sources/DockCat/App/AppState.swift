import AppKit
import DockCatCore
import OSLog

@MainActor
final class AppState: ObservableObject {
    private enum InterruptedFlow {
        case initialPresentation(DockCatNotification)
        case replacement(DockCatNotification)
        case dismissal(DockCatNotification)
    }

    @Published private(set) var current: DockCatNotification?
    @Published private(set) var catState: CatState = .sleeping
    @Published var isPaused = false
    let settings = SettingsStore()
    private lazy var systemNotificationSource = SystemNotificationAccessibilitySource(
        eventHandler: { [weak self] event in self?.receive(sourceEvent: event) },
        outcomeHandler: { _ in }
    )
    lazy var systemNotificationAccess: SystemNotificationAccessController = {
        let controller = SystemNotificationAccessController(
            enabled: settings.preferences.systemNotificationsEnabled,
            source: systemNotificationSource,
            startImmediately: false
        )
        systemNotificationSource.setOutcomeHandler { [weak controller] outcome in
            guard let controller else { return }
            switch outcome {
            case .active: controller.sourceDidStart()
            case .degraded: controller.sourceDidDegrade()
            case .unavailable: controller.sourceDidFailToStart()
            case .permissionRequired: controller.sourceDidLosePermission()
            }
        }
        controller.refresh()
        return controller
    }()

    private let queue = DockCatCore.NotificationQueue()
    private lazy var systemNotificationPipeline = SystemNotificationPipeline(
        queue: queue, ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.example.DockCat"
    )
    private var machine = CatStateMachine()
    private let catWindow = CatWindowController()
    private let cardWindow = CardWindowController()
    private let locator = DockLocator()
    private var flowTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var interruptedFlow: InterruptedFlow?
    private var screenMonitor: ScreenChangeMonitor?
    private let logger = Logger(subsystem: "com.example.DockCat", category: "AppState")

    func start() {
        systemNotificationAccess.refresh()
        reposition()
        catWindow.showSleeping()
        cardWindow.onDismiss = { [weak self] in self?.dismissCurrent() }
        screenMonitor = ScreenChangeMonitor { [weak self] in self?.reposition() }
    }

    func stop() { systemNotificationAccess.shutdown(); flowTask?.cancel(); timeoutTask?.cancel(); cardWindow.cancelPresentationAnimation(); screenMonitor?.stop(); screenMonitor = nil }

    func setSystemNotificationsEnabled(_ enabled: Bool) {
        settings.preferences.systemNotificationsEnabled = enabled
        systemNotificationAccess.setEnabled(enabled)
    }

    func sendTest(persistent: Bool = false) {
        submit(.init(sourceName: "DockCat", title: persistent ? "Persistent alert" : "Hello from DockCat",
                     message: persistent ? "Close this card when you are ready." : "The cat delivered this test notification.",
                     presentation: persistent ? .persistent : .transient(duration: settings.preferences.defaultTransientDuration)))
    }

    func submit(_ notification: DockCatNotification) {
        guard settings.preferences.enabled else { return }
        Task {
            await queue.setLimit(settings.preferences.queueLimit)
            let result = await queue.enqueue(notification)
            logger.info("Notification received: \(notification.id, privacy: .public), result: \(String(describing: result), privacy: .public)")
            guard result == .accepted, !isPaused else { return }
            beginFlowIfNeeded()
        }
    }

    func receive(sourceEvent: NotificationSourceEvent) {
        switch sourceEvent {
        case .notification(let notification): submit(notification)
        case .accessibilitySnapshot(let snapshot):
            guard settings.preferences.enabled else { return }
            Task {
                await queue.setLimit(settings.preferences.queueLimit)
                let result = await systemNotificationPipeline.ingest(
                    snapshot, transientDuration: settings.preferences.defaultTransientDuration
                )
                logger.info("Accessibility notification result: \(String(describing: result), privacy: .public)")
                guard result == .enqueued, !isPaused else { return }
                beginFlowIfNeeded()
            }
        }
    }

    func receive(url: URL) {
        do { submit(try URLSchemeParser(defaultDuration: settings.preferences.defaultTransientDuration).parse(url)) }
        catch { logger.error("URL notification rejected: \(String(describing: error), privacy: .public)") }
    }

    func refreshPlacement() { reposition() }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
        Task { await queue.setPaused(paused) }
        if paused {
            timeoutTask?.cancel()
            cardWindow.cancelPresentationAnimation()
            _ = machine.handle(.pause); catState = machine.state
            catWindow.pause()
        } else {
            _ = machine.handle(.resume); catState = machine.state
            catWindow.resume()
            if let current, machine.state == .waitingForDismissal { scheduleTimeoutIfNeeded(current) }
            continueFlowIfNeeded()
        }
    }

    func dismissCurrent() {
        guard current != nil else { return }
        timeoutTask?.cancel()
        advanceAfterDismissal(event: .userDismissed)
    }

    private func beginFlowIfNeeded() {
        guard flowTask == nil, current == nil, !isPaused else { return }
        flowTask = Task { [weak self] in
            guard let self, let item = await queue.next() else { self?.flowTask = nil; return }
            current = item
            await transition(.notificationAvailable, animation: .wake)
            await transition(.animationCompleted, animation: .pickUp)
            await transition(.animationCompleted, animation: .walkToPresentation)
            _ = machine.handle(.animationCompleted); updateState()
            await presentInitial(item)
        }
    }

    private func continueFlowIfNeeded() {
        guard flowTask == nil, !isPaused else { return }
        guard let interruptedFlow else { beginFlowIfNeeded(); return }
        flowTask = Task { [weak self] in
            guard let self else { return }
            switch interruptedFlow {
            case .initialPresentation(let item): await presentInitial(item)
            case .replacement(let item): await presentReplacement(item)
            case .dismissal(let item): await finishDismissal(item)
            }
        }
    }

    private func presentInitial(_ item: DockCatNotification) async {
        catWindow.prepareHandoffPose()
        let result = await cardWindow.present(notification: item, preferences: settings.preferences, from: catWindow.handoffSourceRect(), reducedMotion: settings.effectiveReducedMotion)
        guard PresentationChoreography.shouldAcceptPresentationCompletion(result), current?.id == item.id else {
            let shouldRetry = !Task.isCancelled && current?.id == item.id && (isPaused || machine.state == .presenting)
            if shouldRetry { interruptedFlow = .initialPresentation(item) }
            flowTask = nil
            if shouldRetry { continueFlowIfNeeded() }
            return
        }
        interruptedFlow = nil
        catWindow.completeHandoffPose()
        _ = machine.handle(.cardPresented); updateState()
        scheduleTimeoutIfNeeded(item)
        flowTask = nil
    }

    private func presentReplacement(_ item: DockCatNotification) async {
        let result = await cardWindow.replace(notification: item, preferences: settings.preferences, reducedMotion: settings.effectiveReducedMotion)
        guard result == .completed, current?.id == item.id else {
            let shouldRetry = !Task.isCancelled && current?.id == item.id && (isPaused || machine.state == .presenting)
            if shouldRetry { interruptedFlow = .replacement(item) }
            flowTask = nil
            if shouldRetry { continueFlowIfNeeded() }
            return
        }
        interruptedFlow = nil
        _ = machine.handle(.cardPresented); updateState()
        scheduleTimeoutIfNeeded(item)
        flowTask = nil
    }

    private func finishDismissal(_ item: DockCatNotification) async {
        let result = await cardWindow.dismissActive(toward: catWindow.handoffSourceRect(), reducedMotion: settings.effectiveReducedMotion)
        guard result == .completed, current?.id == item.id else {
            let shouldRetry = !Task.isCancelled && current?.id == item.id && (isPaused || machine.state == .dismissingCard)
            if shouldRetry { interruptedFlow = .dismissal(item) }
            flowTask = nil
            if shouldRetry { continueFlowIfNeeded() }
            return
        }
        interruptedFlow = nil
        current = nil
        catWindow.hideCarriedCard()
        _ = machine.handle(.cardDismissed); updateState()
        _ = await queue.completeCurrent()
        await catWindow.animate(.walkHome, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
        _ = machine.handle(.animationCompleted); updateState()
        await catWindow.animate(.settle, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
        _ = machine.handle(.animationCompleted); updateState()
        flowTask = nil
        beginFlowIfNeeded()
    }

    private func transition(_ event: CatEvent, animation: CatAnimation) async {
        guard machine.handle(event) else { logger.error("Invalid transition from \(self.machine.state.rawValue)"); return }
        updateState()
        await catWindow.animate(animation, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
    }

    private func scheduleTimeoutIfNeeded(_ item: DockCatNotification) {
        guard case .transient(let duration) = item.presentation else { return }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.advanceAfterDismissal(event: .transientExpired)
        }
    }

    private func advanceAfterDismissal(event: CatEvent) {
        guard flowTask == nil || machine.state == .waitingForDismissal else { return }
        guard machine.handle(event) else { return }
        updateState()
        let dismissed = current
        flowTask = Task { [weak self] in
            guard let self else { return }
            if settings.preferences.remainForQueuedMessages, await queue.hasPending() {
                _ = await queue.completeCurrent()
                guard let next = await queue.next() else { flowTask = nil; return }
                current = next
                _ = machine.handle(.nextNotificationAvailable); updateState()
                await presentReplacement(next)
            } else {
                _ = machine.handle(.queueEmpty); updateState()
                guard let dismissed else { flowTask = nil; return }
                await finishDismissal(dismissed)
            }
            _ = dismissed
        }
    }

    private func updateState() { catState = machine.state; logger.debug("Cat state: \(self.catState.rawValue, privacy: .public)") }
    private func reposition() {
        let geometry = locator.locate(preferences: settings.preferences)
        catWindow.position(at: geometry.sleepingPoint, presentationPoint: geometry.presentationPoint, dockEdge: geometry.edge)
        cardWindow.position(above: geometry.presentationPoint, offset: settings.preferences.cardOffset)
    }
}
