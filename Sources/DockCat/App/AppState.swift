import AppKit
import DockCatCore
import OSLog

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var current: DockCatNotification?
    @Published private(set) var catState: CatState = .sleeping
    @Published var isPaused = false
    let settings = SettingsStore()

    private let queue = DockCatCore.NotificationQueue()
    private var machine = CatStateMachine()
    private let catWindow = CatWindowController()
    private let cardWindow = CardWindowController()
    private let locator = DockLocator()
    private var flowTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var screenMonitor: ScreenChangeMonitor?
    private let logger = Logger(subsystem: "com.example.DockCat", category: "AppState")

    func start() {
        reposition()
        catWindow.showSleeping()
        cardWindow.onDismiss = { [weak self] in self?.dismissCurrent() }
        screenMonitor = ScreenChangeMonitor { [weak self] in self?.reposition() }
    }

    func stop() { flowTask?.cancel(); timeoutTask?.cancel(); cardWindow.cancelPresentationAnimation(); screenMonitor?.stop(); screenMonitor = nil }

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
            beginFlowIfNeeded()
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
            catWindow.prepareHandoffPose()
            let result = await cardWindow.present(notification: item, preferences: settings.preferences, from: catWindow.handoffSourceRect(), reducedMotion: settings.effectiveReducedMotion)
            guard PresentationChoreography.shouldAcceptPresentationCompletion(result), current?.id == item.id else { flowTask = nil; return }
            catWindow.completeHandoffPose()
            _ = machine.handle(.cardPresented); updateState()
            scheduleTimeoutIfNeeded(item)
            flowTask = nil
        }
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
            _ = await queue.completeCurrent()
            if settings.preferences.remainForQueuedMessages, await queue.hasPending(), let next = await queue.next() {
                current = next
                _ = machine.handle(.nextNotificationAvailable); updateState()
                let result = await cardWindow.replace(notification: next, preferences: settings.preferences, reducedMotion: settings.effectiveReducedMotion)
                guard result == .completed, current?.id == next.id else { flowTask = nil; return }
                _ = machine.handle(.cardPresented); updateState()
                scheduleTimeoutIfNeeded(next)
            } else {
                current = nil
                _ = machine.handle(.queueEmpty); updateState()
                let result = await cardWindow.dismissActive(toward: catWindow.handoffSourceRect(), reducedMotion: settings.effectiveReducedMotion)
                guard result == .completed else { flowTask = nil; return }
                catWindow.hideCarriedCard()
                _ = machine.handle(.cardDismissed); updateState()
                await catWindow.animate(.walkHome, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
                _ = machine.handle(.animationCompleted); updateState()
                await catWindow.animate(.settle, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
                _ = machine.handle(.animationCompleted); updateState()
            }
            _ = dismissed
            flowTask = nil
            beginFlowIfNeeded()
        }
    }

    private func updateState() { catState = machine.state; logger.debug("Cat state: \(self.catState.rawValue, privacy: .public)") }
    private func reposition() {
        let geometry = locator.locate(preferences: settings.preferences)
        catWindow.position(at: geometry.sleepingPoint, presentationPoint: geometry.presentationPoint, dockEdge: geometry.edge)
        cardWindow.position(above: geometry.presentationPoint, offset: settings.preferences.cardOffset)
    }
}
