import AppKit
import DockCatCore
import OSLog

@MainActor
final class AppState: ObservableObject {
    private lazy var accessibilityElementRegistry = AccessibilityElementRegistry()
    private lazy var nativeBannerDismissalPerformer = NativeBannerDismissalPerformer(registry: accessibilityElementRegistry, client: AccessibilityAPIClient())
    private enum InterruptedFlow {
        case initialPresentation(DockCatNotification)
        case replacement(DockCatNotification)
        case dismissal(DockCatNotification)

        var effect: CatCoordinatorEffect {
            switch self {
            case .initialPresentation: .presentInitialCard
            case .replacement: .replaceActiveCard
            case .dismissal: .dismissExpandedCard
            }
        }
    }

    @Published private(set) var current: DockCatNotification?
    @Published private(set) var catState: CatState = .sleeping
    @Published var isPaused = false
    let settings = SettingsStore()
    private lazy var systemNotificationSource = SystemNotificationAccessibilitySource(
        dismissalRegistry: accessibilityElementRegistry,
        eventHandler: { [weak self] event in self?.receive(sourceEvent: event) },
        outcomeHandler: { _ in }
    )
    lazy var systemNotificationAccess: SystemNotificationAccessController = {
        let controller = SystemNotificationAccessController(
            enabled: settings.preferences.systemNotificationsEnabled,
            source: systemNotificationSource,
            startImmediately: false
        )
        systemNotificationSource.setOutcomeHandler { [weak controller, weak self] outcome in
            guard let controller else { return }
            switch outcome {
            case .active: controller.sourceDidStart()
            case .degraded: controller.sourceDidDegrade()
            case .unavailable: controller.sourceDidBecomeUnavailable()
            case .permissionRequired:
                controller.sourceDidLosePermission()
                self?.clearExternalNotifications()
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
    private var recoveryTask: Task<Void, Never>?
    private var isRecovering = false
    private var recoveryGate = CatRecoveryGate()
    private var lifecycleReconciliationTask: Task<Void, Never>?
    private var deferredExternalUpdates = Set<ExternalNotificationIdentity>()
    private var deferredExternalDisappearances = Set<ExternalNotificationIdentity>()
    private var interruptedFlow: InterruptedFlow?
    private var screenMonitor: ScreenChangeMonitor?
    private let logger = Logger(subsystem: "com.example.DockCat", category: "AppState")

    func start() {
        systemNotificationAccess.refresh()
        reposition()
        catWindow.showSleeping()
        cardWindow.onDismiss = { [weak self] in self?.dismissCurrent() }
        screenMonitor = ScreenChangeMonitor { [weak self] in self?.reposition() }
        lifecycleReconciliationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                let outcomes = await systemNotificationPipeline.reconcile()
                if outcomes.contains(.removedCurrent) { dismissSourceCurrent() }
            }
        }
    }

    func stop() { clearExternalNotifications(); systemNotificationAccess.shutdown(); flowTask?.cancel(); timeoutTask?.cancel(); recoveryTask?.cancel(); lifecycleReconciliationTask?.cancel(); lifecycleReconciliationTask = nil; cardWindow.cancelPresentationAnimation(); screenMonitor?.stop(); screenMonitor = nil }

    private func clearExternalNotifications() {
        Task {
            let outcomes = await systemNotificationPipeline.sourceStopped()
            if outcomes.contains(.removedCurrent) { dismissSourceCurrent() }
        }
    }

    func setSystemNotificationsEnabled(_ enabled: Bool) {
        settings.preferences.systemNotificationsEnabled = enabled
        if !enabled { clearExternalNotifications() }
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
        case .notification(let notification), .oneShot(let notification): submit(notification)
        case .appeared(let external): submit(external.notification)
        case .updated(let external): handleExternalUpdate(external.notification)
        case .disappeared(let identity): handleExternalDisappearance(identity)
        case .accessibilitySnapshot(let snapshot):
            guard settings.preferences.enabled else { return }
            Task {
                await queue.setLimit(settings.preferences.queueLimit)
                let result = await systemNotificationPipeline.ingest(
                    snapshot, transientDuration: settings.preferences.defaultTransientDuration
                )
                logger.info("Accessibility notification result: \(String(describing: result), privacy: .public)")
                if settings.preferences.isNativeBannerDismissalEnabled,
                   systemNotificationAccess.health.isHealthy,
                   let request = await systemNotificationPipeline.takeDismissalRequest() {
                    let exclusions = Set(DockCatPreferences.normalizedBundleIdentifiers(
                        settings.preferences.nativeBannerDismissalExcludedBundleIdentifiers
                    ))
                    let outcome = nativeBannerDismissalPerformer.perform(
                        token: request.tokenIdentifier, sourceBundleIdentifier: request.sourceBundleIdentifier,
                        notificationSubtreePath: request.notificationSubtreePath,
                        stableContainerIdentifier: request.stableContainerIdentifier, excluded: exclusions,
                        ownBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.example.DockCat"
                    )
                    logger.info("Native banner dismissal outcome=\(String(describing: outcome), privacy: .public)")
                    if outcome == .permissionRequired { systemNotificationAccess.sourceDidLosePermission() }
                }
                guard !isPaused else { return }
                switch result {
                case .enqueued: beginFlowIfNeeded()
                case .updatedCurrent: await replaceUpdatedCurrent()
                case .removedCurrent: dismissSourceCurrent()
                default: break
                }
            }
        }
    }

    private func handleExternalUpdate(_ notification: DockCatNotification) {
        Task { _ = await queue.updateExternal(notification); await replaceUpdatedCurrent() }
    }

    private func replaceUpdatedCurrent() async {
        guard let queued = await queue.currentNotification(), let identity = queued.externalIdentity else { return }
        guard flowTask == nil, !isRecovering, machine.state == .waitingForDismissal else {
            deferredExternalUpdates.insert(identity)
            return
        }
        let updated = queued
        deferredExternalUpdates.remove(identity)
        timeoutTask?.cancel()
        current = updated
        startFlow(with: .notificationUpdated)
    }

    private func handleExternalDisappearance(_ identity: ExternalNotificationIdentity) {
        Task {
            let result = await queue.removeExternal(identity)
            if result == .removedCurrent { dismissSourceCurrent() }
        }
    }

    private func dismissSourceCurrent() {
        guard let identity = current?.externalIdentity else { return }
        guard flowTask == nil, !isRecovering, machine.state == .waitingForDismissal else {
            deferredExternalDisappearances.insert(identity)
            return
        }
        deferredExternalDisappearances.remove(identity)
        deferredExternalUpdates.remove(identity)
        timeoutTask?.cancel()
        startDismissal(with: .sourceDisappeared)
    }

    /// Applies lifecycle work that arrived while wake/travel/card animation owned the flow.
    /// Disappearance wins over an update because its queue item has already been removed.
    private func applyDeferredExternalLifecycle() async {
        guard flowTask == nil, machine.state == .waitingForDismissal,
              let identity = current?.externalIdentity else { return }
        if deferredExternalDisappearances.contains(identity) {
            dismissSourceCurrent()
        } else if deferredExternalUpdates.contains(identity) {
            await replaceUpdatedCurrent()
        }
    }

    func receive(url: URL) {
        do { submit(try URLSchemeParser(defaultDuration: settings.preferences.defaultTransientDuration).parse(url)) }
        catch { logger.error("URL notification rejected: \(String(describing: error), privacy: .public)") }
    }

    func refreshPlacement() { reposition() }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        let event: CatEvent = paused ? .pause : .resume
        guard case .accepted(let transition) = apply(event) else { return }
        isPaused = paused
        Task { [weak self] in
            guard let self else { return }
            await queue.setPaused(paused)
            _ = await execute(transition.effect)
        }
    }

    func dismissCurrent() {
        guard current != nil else { return }
        timeoutTask?.cancel()
        startDismissal(with: .userDismissed)
    }

    private func beginFlowIfNeeded() {
        guard flowTask == nil, current == nil, !isPaused, !isRecovering else { return }
        flowTask = Task { [weak self] in
            guard let self, let item = await queue.next() else { self?.flowTask = nil; return }
            current = item
            await process(startingWith: .notificationAvailable)
            await flowFinished()
        }
    }

    private func continueFlowIfNeeded() {
        guard flowTask == nil, !isPaused, !isRecovering else { return }
        guard let interruptedFlow else { beginFlowIfNeeded(); return }
        flowTask = Task { [weak self] in
            guard let self else { return }
            let outcome: CatEffectExecutionOutcome
            switch interruptedFlow {
            case .initialPresentation: outcome = await execute(.presentInitialCard)
            case .replacement: outcome = await execute(.replaceActiveCard)
            case .dismissal: outcome = await execute(.dismissExpandedCard)
            }
            switch CatEffectChainPolicy.action(after: outcome) {
            case .submit(let event): await process(startingWith: event)
            case .recover: scheduleRecovery(afterEffect: interruptedFlow.effect)
            case .stop: break
            }
            await flowFinished()
        }
    }

    /// The only production entry point that mutates the state machine. It publishes and
    /// diagnoses a decision exactly once, and schedules fail-closed recovery on rejection.
    private func apply(_ event: CatEvent) -> CatTransitionResult {
        let result = machine.handle(event)
        switch result {
        case .accepted(let transition):
            catState = transition.nextState
            logger.info(
                "Cat transition previous=\(transition.previousState.rawValue, privacy: .public) event=\(transition.event.rawValue, privacy: .public) next=\(transition.nextState.rawValue, privacy: .public) effect=\(transition.effect.rawValue, privacy: .public)"
            )
        case .rejected(let rejection):
            logger.error(
                "Cat transition rejected state=\(rejection.currentState.rawValue, privacy: .public) event=\(rejection.event.rawValue, privacy: .public) reason=\(rejection.reason.rawValue, privacy: .public) recovery=true"
            )
            scheduleRecovery(after: rejection)
        }
        return result
    }

    /// Runs a bounded state/effect chain. Each successful async effect emits at most one
    /// next semantic event; a cancellation or failure ends the chain immediately.
    private func process(startingWith firstEvent: CatEvent) async {
        var nextEvent: CatEvent? = firstEvent
        while let event = nextEvent, !Task.isCancelled, !isRecovering {
            while isPaused, !Task.isCancelled, !isRecovering {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard !Task.isCancelled, !isRecovering else { return }
            let result = apply(event)
            guard let effect = CatEffectChainPolicy.effect(for: result) else { return }
            switch CatEffectChainPolicy.action(after: await execute(effect)) {
            case .submit(let emittedEvent): nextEvent = emittedEvent
            case .stop: nextEvent = nil
            case .recover:
                scheduleRecovery(afterEffect: effect)
                return
            }
        }
    }

    private func execute(_ effect: CatCoordinatorEffect) async -> CatEffectExecutionOutcome {
        switch effect {
        case .wake:
            await catWindow.animate(.wake, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
            return Task.isCancelled ? .cancelled : .completed(nextEvent: .animationCompleted)
        case .pickUpCard:
            await catWindow.animate(.pickUp, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
            return Task.isCancelled ? .cancelled : .completed(nextEvent: .animationCompleted)
        case .travelToPresentation:
            await catWindow.animate(.walkToPresentation, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
            return Task.isCancelled ? .cancelled : .completed(nextEvent: .animationCompleted)
        case .presentInitialCard:
            guard let item = current else { return failClosed(effect) }
            catWindow.prepareHandoffPose()
            let result = await cardWindow.present(
                notification: item,
                preferences: settings.preferences,
                from: catWindow.handoffSourceRect(),
                reducedMotion: settings.effectiveReducedMotion
            )
            guard PresentationChoreography.shouldAcceptPresentationCompletion(result), current?.id == item.id else {
                return handleExpectedInterruption(.initialPresentation(item), item: item, state: .presenting)
            }
            interruptedFlow = nil
            return .completed(nextEvent: .cardPresented)
        case .enterWaitingState:
            interruptedFlow = nil
            catWindow.completeHandoffPose()
            return .completed(nextEvent: nil)
        case .replaceActiveCard:
            guard let item = current else { return failClosed(effect) }
            let result = await cardWindow.replace(
                notification: item,
                preferences: settings.preferences,
                reducedMotion: settings.effectiveReducedMotion
            )
            guard result == .completed, current?.id == item.id else {
                return handleExpectedInterruption(.replacement(item), item: item, state: .presenting)
            }
            interruptedFlow = nil
            return .completed(nextEvent: .cardPresented)
        case .selectNextQueueAction:
            if settings.preferences.remainForQueuedMessages, await queue.hasPending() {
                _ = await queue.completeCurrent()
                guard let next = await queue.next() else { return failClosed(effect) }
                current = next
                return .completed(nextEvent: .nextNotificationAvailable)
            }
            return .completed(nextEvent: .queueEmpty)
        case .dismissExpandedCard:
            guard let item = current else { return failClosed(effect) }
            let result = await cardWindow.dismissActive(
                toward: catWindow.handoffSourceRect(),
                reducedMotion: settings.effectiveReducedMotion
            )
            guard result == .completed, current?.id == item.id else {
                return handleExpectedInterruption(.dismissal(item), item: item, state: .dismissingCard)
            }
            interruptedFlow = nil
            current = nil
            catWindow.hideCarriedCard()
            _ = await queue.completeCurrent()
            return .completed(nextEvent: .cardDismissed)
        case .travelHome:
            await catWindow.animate(.walkHome, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
            return Task.isCancelled ? .cancelled : .completed(nextEvent: .animationCompleted)
        case .settleToSleep:
            await catWindow.animate(.settle, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
            return Task.isCancelled ? .cancelled : .completed(nextEvent: .animationCompleted)
        case .pauseVisualWork:
            timeoutTask?.cancel()
            cardWindow.cancelPresentationAnimation()
            catWindow.pause()
            return .completed(nextEvent: nil)
        case .resumePriorWork:
            catWindow.resume()
            Task { [weak self] in
                await Task.yield()
                guard let self, !self.isPaused, !self.isRecovering else { return }
                if let current = self.current, self.machine.state == .waitingForDismissal {
                    self.scheduleTimeoutIfNeeded(current)
                }
                self.continueFlowIfNeeded()
            }
            return .completed(nextEvent: nil)
        case .none:
            return .completed(nextEvent: nil)
        }
    }

    private func handleExpectedInterruption(
        _ interruption: InterruptedFlow,
        item: DockCatNotification,
        state expectedState: CatState
    ) -> CatEffectExecutionOutcome {
        guard !Task.isCancelled, current?.id == item.id,
              isPaused || machine.state == expectedState else { return .cancelled }
        interruptedFlow = interruption
        return .cancelled
    }

    private func failClosed(_ effect: CatCoordinatorEffect) -> CatEffectExecutionOutcome {
        logger.fault("Cat coordinator effect failed effect=\(effect.rawValue, privacy: .public) recovery=true")
        return .failed
    }

    private func flowFinished() async {
        flowTask = nil
        guard !Task.isCancelled, !isPaused, !isRecovering else { return }
        if interruptedFlow != nil {
            continueFlowIfNeeded()
            return
        }
        if machine.state == .waitingForDismissal {
            await applyDeferredExternalLifecycle()
            if flowTask == nil, let current { scheduleTimeoutIfNeeded(current) }
        } else if machine.state == .sleeping {
            beginFlowIfNeeded()
        }
    }

    private func scheduleTimeoutIfNeeded(_ item: DockCatNotification) {
        guard case .transient(let duration) = item.presentation else { return }
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            guard self?.current?.id == item.id else { return }
            self?.timeoutTask = nil
            self?.startDismissal(with: .transientExpired)
        }
    }

    private func startDismissal(with event: CatEvent) {
        guard flowTask == nil, !isPaused, !isRecovering,
              machine.state == .waitingForDismissal else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        startFlow(with: event)
    }

    private func startFlow(with event: CatEvent) {
        guard flowTask == nil, !isRecovering else { return }
        flowTask = Task { [weak self] in
            guard let self else { return }
            await process(startingWith: event)
            await flowFinished()
        }
    }

    private func scheduleRecovery(after rejection: CatTransitionRejection) {
        guard recoveryGate.requestRecovery() else { return }
        isRecovering = true
        recoveryTask = Task { [weak self] in
            await self?.recoverFromDivergence(
                context: "event=\(rejection.event.rawValue) reason=\(rejection.reason.rawValue)"
            )
        }
    }

    private func scheduleRecovery(afterEffect effect: CatCoordinatorEffect) {
        guard recoveryGate.requestRecovery() else { return }
        isRecovering = true
        recoveryTask = Task { [weak self] in
            await self?.recoverFromDivergence(context: "effect=\(effect.rawValue)")
        }
    }

    /// Fail-closed policy: drop only the inconsistent active item, preserve pending items,
    /// reset UI and state to sleeping, then allow the next pending item to start once.
    private func recoverFromDivergence(context: String) async {
        let interruptedTask = flowTask
        interruptedTask?.cancel()
        timeoutTask?.cancel()
        cardWindow.cancelPresentationAnimation()
        catWindow.resetToSleeping()
        cardWindow.forceHide()
        await interruptedTask?.value
        interruptedFlow = nil
        deferredExternalUpdates.removeAll()
        deferredExternalDisappearances.removeAll()
        current = nil
        _ = await queue.completeCurrent()
        await queue.setPaused(false)
        isPaused = false
        let recovery = machine.recoverToSleeping()
        catState = recovery.safeState
        flowTask = nil
        timeoutTask = nil
        logger.fault(
            "Cat coordinator recovered previous=\(recovery.previousState.rawValue, privacy: .public) safe=\(recovery.safeState.rawValue, privacy: .public) context=\(context, privacy: .public)"
        )
        isRecovering = false
        recoveryGate.recoveryCompleted()
        recoveryTask = nil
        beginFlowIfNeeded()
    }

    private func reposition() {
        let geometry = locator.locate(preferences: settings.preferences)
        catWindow.position(at: geometry.sleepingPoint, presentationPoint: geometry.presentationPoint, dockEdge: geometry.edge)
        cardWindow.position(above: geometry.presentationPoint, offset: settings.preferences.cardOffset)
    }
}
