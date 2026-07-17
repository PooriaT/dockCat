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

    private struct DeferredExternalUpdate {
        let notification: DockCatNotification
        let revision: NotificationQueueRevision
    }

    private struct DeferredExternalRemoval {
        let notification: DockCatNotification
        let revision: NotificationQueueRevision
    }

    @Published private(set) var current: DockCatNotification?
    @Published private(set) var catState: CatState = .sleeping
    @Published private(set) var isPaused = false
    @Published private(set) var isPauseTransitioning = false
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
    private var pauseTransitionTask: Task<Void, Never>?
    private var isRecovering = false
    private var recoveryGate = CatRecoveryGate()
    private var requestedPauseState = false
    private var observedQueueRevision: NotificationQueueRevision = 0
    private var currentProjectionRevision: NotificationQueueRevision = 0
    private var lifecycleReconciliationTask: Task<Void, Never>?
    private var deferredExternalUpdates: [ExternalNotificationIdentity: DeferredExternalUpdate] = [:]
    private var deferredExternalDisappearances: [ExternalNotificationIdentity: DeferredExternalRemoval] = [:]
    private var dismissingNotification: DockCatNotification?
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
                for outcome in outcomes { await self.applyExternalMutation(outcome.queueMutation) }
            }
        }
    }

    func stop() { clearExternalNotifications(); systemNotificationAccess.shutdown(); flowTask?.cancel(); timeoutTask?.cancel(); recoveryTask?.cancel(); pauseTransitionTask?.cancel(); lifecycleReconciliationTask?.cancel(); lifecycleReconciliationTask = nil; cardWindow.cancelPresentationAnimation(); screenMonitor?.stop(); screenMonitor = nil }

    private func clearExternalNotifications() {
        Task {
            let outcomes = await systemNotificationPipeline.sourceStopped()
            for outcome in outcomes { await applyExternalMutation(outcome.queueMutation) }
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
            observeQueueRevision((await queue.setLimit(settings.preferences.queueLimit)).revision)
            let result = await queue.enqueue(notification)
            logger.info("Notification received: \(notification.id, privacy: .public), result: \(String(describing: result), privacy: .public)")
            _ = observeQueueRevision(result.revision)
            guard result.wasAccepted else { return }
            beginFlowIfNeeded()
        }
    }

    func receive(sourceEvent: NotificationSourceEvent) {
        switch sourceEvent {
        case .notification(let notification), .oneShot(let notification): submit(notification)
        case .appeared(let external): handleExternalAppearance(external.notification)
        case .updated(let external): handleExternalUpdate(external.notification)
        case .disappeared(let identity): handleExternalDisappearance(identity)
        case .accessibilitySnapshot(let snapshot):
            guard settings.preferences.enabled else { return }
            Task {
                observeQueueRevision((await queue.setLimit(settings.preferences.queueLimit)).revision)
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
                await applyExternalMutation(result.queueMutation)
            }
        }
    }

    private func handleExternalAppearance(_ notification: DockCatNotification) {
        guard settings.preferences.enabled else { return }
        Task {
            observeQueueRevision((await queue.setLimit(settings.preferences.queueLimit)).revision)
            await applyExternalMutation(await queue.enqueueAppeared(notification))
        }
    }

    private func handleExternalUpdate(_ notification: DockCatNotification) {
        Task { await applyExternalMutation(await queue.updateExternal(notification)) }
    }

    private func applyExternalMutation(
        _ mutation: DockCatCore.NotificationQueue.ExternalMutationResult?
    ) async {
        guard let mutation else { return }
        guard observeQueueRevision(mutation.revision) else {
            // A stale insertion is still stored. Starting a claim is safe because the actor
            // will return whichever current item is authoritative at its latest revision.
            switch mutation {
            case .inserted:
                beginFlowIfNeeded()
            case .updatedCurrent, .unchangedCurrent, .removedCurrent:
                await reconcileSupersededExternalMutation(mutation)
            case .updatedPending, .unchangedPending, .removedPending, .notFound, .duplicate, .full:
                break
            }
            return
        }
        switch mutation {
        case .inserted:
            beginFlowIfNeeded()
        case .updatedCurrent(let notification, let revision):
            replaceUpdatedCurrent(notification, revision: revision)
        case .unchangedCurrent(let notification, let revision):
            if current != notification { replaceUpdatedCurrent(notification, revision: revision) }
        case .updatedPending, .unchangedPending, .removedPending, .notFound, .duplicate, .full:
            break
        case .removedCurrent(let notification, _, let revision):
            if current?.id == notification.id {
                dismissSourceCurrent(notification, revision: revision)
            } else if dismissingNotification?.id == notification.id {
                if let identity = notification.externalIdentity {
                    deferredExternalDisappearances.removeValue(forKey: identity)
                    deferredExternalUpdates.removeValue(forKey: identity)
                }
            } else {
                await reconcileSupersededExternalMutation(mutation)
            }
        }
    }

    /// A newer queue result may reach the main actor before an older lifecycle result.
    /// Consult the latest identity-only snapshot and apply the older payload only when it
    /// still describes the actor's authoritative current state. Superseded results are no-ops.
    private func reconcileSupersededExternalMutation(
        _ mutation: DockCatCore.NotificationQueue.ExternalMutationResult
    ) async {
        let snapshot = await queue.snapshot()
        _ = observeQueueRevision(snapshot.revision)

        switch mutation {
        case .updatedCurrent(let notification, let revision),
             .unchangedCurrent(let notification, let revision):
            guard snapshot.currentID == notification.id,
                  current?.id == notification.id,
                  revision >= currentProjectionRevision else { return }
            replaceUpdatedCurrent(notification, revision: revision)
        case .removedCurrent(let notification, _, let revision):
            guard snapshot.currentID != notification.id,
                  current?.id == notification.id,
                  revision >= currentProjectionRevision else { return }
            dismissSourceCurrent(notification, revision: revision)
        case .inserted, .updatedPending, .unchangedPending, .removedPending,
             .notFound, .duplicate, .full:
            break
        }
    }

    private func replaceUpdatedCurrent(_ notification: DockCatNotification, revision: NotificationQueueRevision) {
        guard let identity = notification.externalIdentity else { return }
        guard externalLifecycleIsStable else {
            if deferredExternalUpdates[identity]?.revision ?? 0 <= revision {
                deferredExternalUpdates[identity] = .init(notification: notification, revision: revision)
            }
            return
        }
        guard current?.id == notification.id else {
            failQueueReconciliation(context: "external-update identity mismatch")
            return
        }
        deferredExternalUpdates.removeValue(forKey: identity)
        timeoutTask?.cancel()
        projectCurrent(notification, revision: revision)
        startFlow(with: .notificationUpdated)
    }

    private func handleExternalDisappearance(_ identity: ExternalNotificationIdentity) {
        Task { await applyExternalMutation(await queue.removeExternal(identity)) }
    }

    private func dismissSourceCurrent(_ notification: DockCatNotification, revision: NotificationQueueRevision) {
        guard let identity = notification.externalIdentity else { return }
        guard externalLifecycleIsStable else {
            if deferredExternalDisappearances[identity]?.revision ?? 0 <= revision {
                deferredExternalDisappearances[identity] = .init(notification: notification, revision: revision)
            }
            deferredExternalUpdates.removeValue(forKey: identity)
            return
        }
        guard current?.id == notification.id else {
            failQueueReconciliation(context: "external-removal identity mismatch")
            return
        }
        deferredExternalDisappearances.removeValue(forKey: identity)
        deferredExternalUpdates.removeValue(forKey: identity)
        timeoutTask?.cancel()
        dismissingNotification = notification
        projectNoCurrent(revision: revision)
        startDismissal(with: .sourceDisappeared)
    }

    /// Applies lifecycle work that arrived while wake/travel/card animation owned the flow.
    /// Disappearance wins over an update because its queue item has already been removed.
    private func applyDeferredExternalLifecycle() {
        guard flowTask == nil, machine.state == .waitingForDismissal,
              let identity = current?.externalIdentity else { return }
        if let removal = deferredExternalDisappearances[identity] {
            dismissSourceCurrent(removal.notification, revision: removal.revision)
        } else if let update = deferredExternalUpdates[identity] {
            replaceUpdatedCurrent(update.notification, revision: update.revision)
        }
    }

    func receive(url: URL) {
        do { submit(try URLSchemeParser(defaultDuration: settings.preferences.defaultTransientDuration).parse(url)) }
        catch { logger.error("URL notification rejected: \(String(describing: error), privacy: .public)") }
    }

    func refreshPlacement() { reposition() }

    func setPaused(_ paused: Bool) {
        requestedPauseState = paused
        if pauseTransitionTask == nil, paused == isPaused { return }
        guard pauseTransitionTask == nil else { return }
        isPauseTransitioning = true
        pauseTransitionTask = Task { [weak self] in await self?.drainPauseRequests() }
    }

    /// Coalesces rapid requests while preserving actor-confirmation order. Coordinator
    /// state, timers, and visuals change only after the matching queue outcome returns.
    private func drainPauseRequests() async {
        while !Task.isCancelled, !isRecovering {
            let requested = requestedPauseState
            let outcome = await queue.setPaused(requested)
            guard !Task.isCancelled, !isRecovering else { break }
            guard observeQueueRevision(outcome.revision) else {
                failQueueReconciliation(context: "stale pause decision")
                break
            }

            if flowTask == nil, deferredExternalDisappearances.isEmpty,
               outcome.currentID != current?.id {
                failQueueReconciliation(context: "pause projection mismatch")
                break
            }

            if outcome.isPaused != isPaused {
                let event: CatEvent = outcome.isPaused ? .pause : .resume
                guard case .accepted(let transition) = apply(event) else { break }
                isPaused = outcome.isPaused
                guard executeStateControlEffect(transition.effect) != nil else {
                    failClosedWithoutFlow(transition.effect)
                    break
                }
            }

            if requested == requestedPauseState { break }
        }

        pauseTransitionTask = nil
        isPauseTransitioning = false
        if !isPaused, !isRecovering { continueAfterResume() }
    }

    func dismissCurrent() {
        guard current != nil else { return }
        timeoutTask?.cancel()
        startDismissal(with: .userDismissed)
    }

    private func beginFlowIfNeeded() {
        guard flowTask == nil, current == nil, !isPaused, !isPauseTransitioning,
              !isRecovering else { return }
        flowTask = Task { [weak self] in
            guard let self else { return }
            let decision = await queue.claimNext()
            guard applyClaim(decision) else { flowTask = nil; return }
            guard await reconcileQueueProjection(context: "claim") else { flowTask = nil; return }
            await process(startingWith: .notificationAvailable)
            await flowFinished()
        }
    }

    private func applyClaim(_ decision: DockCatCore.NotificationQueue.ClaimResult) -> Bool {
        guard observeQueueRevision(decision.revision) else {
            failQueueReconciliation(context: "stale claim decision")
            return false
        }
        switch decision {
        case .promoted(let notification, let revision), .current(let notification, let revision):
            projectCurrent(notification, revision: revision)
            return true
        case .paused, .idle:
            return false
        }
    }

    private func continueFlowIfNeeded() {
        guard flowTask == nil, !isPaused, !isPauseTransitioning, !isRecovering else { return }
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
        if let outcome = executeStateControlEffect(effect) { return outcome }

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
            return await selectNextQueueAction(effect: effect)
        case .dismissExpandedCard:
            guard let item = dismissingNotification else { return failClosed(effect) }
            let result = await cardWindow.dismissActive(
                toward: catWindow.handoffSourceRect(),
                reducedMotion: settings.effectiveReducedMotion
            )
            guard result == .completed, dismissingNotification?.id == item.id else {
                return handleExpectedInterruption(.dismissal(item), item: item, state: .dismissingCard)
            }
            interruptedFlow = nil
            dismissingNotification = nil
            catWindow.hideCarriedCard()
            return .completed(nextEvent: .cardDismissed)
        case .travelHome:
            await catWindow.animate(.walkHome, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
            return Task.isCancelled ? .cancelled : .completed(nextEvent: .animationCompleted)
        case .settleToSleep:
            await catWindow.animate(.settle, speed: settings.preferences.animationSpeed, reducedMotion: settings.effectiveReducedMotion)
            return Task.isCancelled ? .cancelled : .completed(nextEvent: .animationCompleted)
        case .pauseVisualWork, .resumePriorWork:
            preconditionFailure("State-control effects are handled before the async effect switch")
        case .none:
            return .completed(nextEvent: nil)
        }
    }

    private func selectNextQueueAction(effect: CatCoordinatorEffect) async -> CatEffectExecutionOutcome {
        // An external disappearance has already removed the actor's current item. Claiming
        // here is the single atomic selection that preserves stay-at-presentation behavior.
        if dismissingNotification != nil, current == nil {
            return await claimAfterExternalRemoval(effect: effect)
        }

        let policy: DockCatCore.NotificationQueue.CompletionPolicy = settings.preferences.remainForQueuedMessages
            ? .advanceImmediately
            : .leavePendingForLater
        let decision = await queue.completeCurrent(policy: policy)
        let isFreshDecision = observeQueueRevision(decision.revision)
        if !isFreshDecision, case .noCurrent = decision {
            // Continue below: a later pending-only mutation may have advanced the observed
            // revision even though the external removal still authoritatively cleared current.
        } else if !isFreshDecision {
            return failClosed(effect)
        }

        switch decision {
        case .advanced(let completed, let next, let revision):
            guard current?.id == completed.id else { return failClosed(effect) }
            projectCurrent(next, revision: revision)
            dismissingNotification = nil
            guard await reconcileQueueProjection(context: "completion and advance") else { return .cancelled }
            return .completed(nextEvent: .nextNotificationAvailable)
        case .completedAndIdle(let completed, let revision),
             .completedWithPending(let completed, _, let revision),
             .pausedAfterCompletion(let completed, _, let revision):
            guard current?.id == completed.id else { return failClosed(effect) }
            projectNoCurrent(revision: revision)
            dismissingNotification = completed
            guard await reconcileQueueProjection(context: "completion without advance") else { return .cancelled }
            return .completed(nextEvent: .queueEmpty)
        case .noCurrent(let revision):
            guard revision >= currentProjectionRevision,
                  let removed = current, removed.externalIdentity != nil else {
                return failClosed(effect)
            }
            // The source actor won the race with timeout/user completion. Treat the
            // projected external item as the removed card and continue normal choreography.
            dismissingNotification = removed
            projectNoCurrent(revision: revision)
            if let identity = removed.externalIdentity {
                deferredExternalUpdates.removeValue(forKey: identity)
                deferredExternalDisappearances.removeValue(forKey: identity)
            }
            return await claimAfterExternalRemoval(effect: effect)
        }
    }

    private func claimAfterExternalRemoval(effect: CatCoordinatorEffect) async -> CatEffectExecutionOutcome {
        guard settings.preferences.remainForQueuedMessages else {
            guard await reconcileQueueProjection(context: "external removal without advance") else {
                return .cancelled
            }
            return .completed(nextEvent: .queueEmpty)
        }

        let claim = await queue.claimNext()
        guard observeQueueRevision(claim.revision) else { return failClosed(effect) }
        switch claim {
        case .promoted(let next, let revision), .current(let next, let revision):
            projectCurrent(next, revision: revision)
            dismissingNotification = nil
            guard await reconcileQueueProjection(context: "claim after external removal") else {
                return .cancelled
            }
            return .completed(nextEvent: .nextNotificationAvailable)
        case .idle:
            guard await reconcileQueueProjection(context: "idle after external removal") else {
                return .cancelled
            }
            return .completed(nextEvent: .queueEmpty)
        case .paused:
            return .completed(nextEvent: .queueEmpty)
        }
    }

    /// Pause/resume effects contain no suspension point, so the visible state is updated in
    /// the same main-actor turn as the state-machine decision.
    private func executeStateControlEffect(
        _ effect: CatCoordinatorEffect
    ) -> CatEffectExecutionOutcome? {
        switch effect {
        case .pauseVisualWork:
            timeoutTask?.cancel()
            cardWindow.cancelPresentationAnimation()
            catWindow.pause()
            return .completed(nextEvent: nil)
        case .resumePriorWork:
            catWindow.resume()
            return .completed(nextEvent: nil)
        default:
            return nil
        }
    }

    private func failClosedWithoutFlow(_ effect: CatCoordinatorEffect) {
        logger.fault("Unexpected state-control effect=\(effect.rawValue, privacy: .public) recovery=true")
        scheduleRecovery(afterEffect: effect)
    }

    private func continueAfterResume() {
        guard !isPaused, !isPauseTransitioning, !isRecovering else { return }
        if machine.state == .waitingForDismissal {
            applyDeferredExternalLifecycle()
            if flowTask != nil { return }
        }
        if let current, machine.state == .waitingForDismissal {
            scheduleTimeoutIfNeeded(current)
        }
        continueFlowIfNeeded()
    }

    private func handleExpectedInterruption(
        _ interruption: InterruptedFlow,
        item: DockCatNotification,
        state expectedState: CatState
    ) -> CatEffectExecutionOutcome {
        let ownedID: UUID? = switch interruption {
        case .dismissal: dismissingNotification?.id
        case .initialPresentation, .replacement: current?.id
        }
        guard !Task.isCancelled, ownedID == item.id,
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
            applyDeferredExternalLifecycle()
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
        guard flowTask == nil, !isPaused, !isPauseTransitioning, !isRecovering,
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

    private func projectCurrent(
        _ notification: DockCatNotification,
        revision: NotificationQueueRevision
    ) {
        guard revision >= currentProjectionRevision else { return }
        current = notification
        currentProjectionRevision = revision
    }

    private func projectNoCurrent(revision: NotificationQueueRevision) {
        guard revision >= currentProjectionRevision else { return }
        current = nil
        currentProjectionRevision = revision
    }

    @discardableResult
    private func observeQueueRevision(_ revision: NotificationQueueRevision) -> Bool {
        guard revision >= observedQueueRevision else {
            logger.error(
                "Stale queue decision revision=\(revision, privacy: .public) observed=\(self.observedQueueRevision, privacy: .public) ignored=true"
            )
            return false
        }
        observedQueueRevision = revision
        return true
    }

    /// Used only at stable decision boundaries; the queue is never polled continuously.
    private func reconcileQueueProjection(context: String) async -> Bool {
        let snapshot = await queue.snapshot()
        guard observeQueueRevision(snapshot.revision), snapshot.matches(projectedCurrent: current) else {
            failQueueReconciliation(context: context)
            return false
        }
        return true
    }

    private func failQueueReconciliation(context: String) {
        logger.fault(
            "Queue projection mismatch revision=\(self.observedQueueRevision, privacy: .public) context=\(context, privacy: .public) recovery=true"
        )
        scheduleRecovery(context: "queue projection: \(context)")
    }

    private func scheduleRecovery(context: String) {
        guard recoveryGate.requestRecovery() else { return }
        isRecovering = true
        recoveryTask = Task { [weak self] in
            await self?.recoverFromDivergence(context: context)
        }
    }

    private func scheduleRecovery(after rejection: CatTransitionRejection) {
        scheduleRecovery(context: "event=\(rejection.event.rawValue) reason=\(rejection.reason.rawValue)")
    }

    private func scheduleRecovery(afterEffect effect: CatCoordinatorEffect) {
        scheduleRecovery(context: "effect=\(effect.rawValue)")
    }

    /// Fail-closed policy: drop only the inconsistent active item, preserve pending items,
    /// reset UI and state to sleeping, then allow the next pending item to start once.
    private func recoverFromDivergence(context: String) async {
        let interruptedTask = flowTask
        interruptedTask?.cancel()
        pauseTransitionTask?.cancel()
        timeoutTask?.cancel()
        cardWindow.cancelPresentationAnimation()
        catWindow.cancelVisualWork()
        cardWindow.forceHide()
        await interruptedTask?.value
        // Cancellation unblocks continuations first. This final reset runs only after the
        // old flow can no longer overwrite the sleeping pose or card visibility.
        catWindow.resetToSleeping()
        cardWindow.forceHide()
        interruptedFlow = nil
        deferredExternalUpdates.removeAll()
        deferredExternalDisappearances.removeAll()
        dismissingNotification = nil
        let completion = await queue.completeCurrent(policy: .leavePendingForLater)
        _ = observeQueueRevision(completion.revision)
        projectNoCurrent(revision: completion.revision)
        requestedPauseState = false
        let pause = await queue.setPaused(false)
        _ = observeQueueRevision(pause.revision)
        isPaused = false
        isPauseTransitioning = false
        pauseTransitionTask = nil
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

    private var externalLifecycleIsStable: Bool {
        flowTask == nil && !isPaused && !isPauseTransitioning && !isRecovering
            && machine.state == .waitingForDismissal
    }

}
