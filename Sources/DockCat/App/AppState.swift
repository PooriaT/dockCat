import AppKit
import DockCatCore
import OSLog

@MainActor
final class AppState: ObservableObject {
    private lazy var accessibilityElementRegistry = AccessibilityElementRegistry()
    private lazy var nativeBannerDismissalPerformer = NativeBannerDismissalPerformer(registry: accessibilityElementRegistry, client: AccessibilityAPIClient())
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
                self?.cancelActiveExternalSession(
                    reason: .permissionLoss, context: "Accessibility permission loss"
                )
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
    private let presentation = PresentationSessionCoordinator()
    private var claimTask: Task<Void, Never>?
    private var disableCleanupTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var pauseTransitionTask: Task<Void, Never>?
    private var isRecovering = false
    private var recoveryGate = CatRecoveryGate()
    private var requestedPauseState = false
    private var observedQueueRevision: NotificationQueueRevision = 0
    private var currentProjectionRevision: NotificationQueueRevision = 0
    private var lifecycleReconciliationTask: Task<Void, Never>?
    private var deferredExternalUpdate: DeferredExternalUpdate?
    private var deferredExternalDisappearance: DeferredExternalRemoval?
    private var dismissingNotification: DockCatNotification?
    private var screenMonitor: ScreenChangeMonitor?
    private var placementRefreshTask: Task<Void, Never>?
    private var placementRevision: UInt64 = 0
    private var lastValidPlacement: DockPlacement?
    private let logger = Logger(subsystem: "com.example.DockCat", category: "AppState")

    func start() {
        systemNotificationAccess.refresh()
        applyNewestPlacement()
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

    func stop() {
        clearExternalNotifications()
        systemNotificationAccess.shutdown()
        claimTask?.cancel()
        disableCleanupTask?.cancel()
        disableCleanupTask = nil
        presentation.cancelSession(reason: .appShutdown)
        recoveryTask?.cancel()
        pauseTransitionTask?.cancel()
        lifecycleReconciliationTask?.cancel()
        lifecycleReconciliationTask = nil
        placementRefreshTask?.cancel()
        placementRefreshTask = nil
        cardWindow.forceHide()
        catWindow.cancelVisualWork()
        screenMonitor?.stop()
        screenMonitor = nil
    }

    private func clearExternalNotifications() {
        Task {
            let outcomes = await systemNotificationPipeline.sourceStopped()
            for outcome in outcomes { await applyExternalMutation(outcome.queueMutation) }
        }
    }

    func setSystemNotificationsEnabled(_ enabled: Bool) {
        settings.preferences.systemNotificationsEnabled = enabled
        if !enabled {
            cancelActiveExternalSession(reason: .sourceShutdown, context: "source disabled")
            clearExternalNotifications()
        }
        systemNotificationAccess.setEnabled(enabled)
    }

    func setDockCatEnabled(_ enabled: Bool) {
        guard settings.preferences.enabled != enabled else { return }
        settings.preferences.enabled = enabled
        if enabled {
            // A disable cleanup may already be inside the queue actor and cannot be
            // withdrawn. Its completion restarts delivery after restoring a clean
            // sleeping projection, so enabling must wait behind it.
            if disableCleanupTask == nil { beginFlowIfNeeded() }
            return
        }
        claimTask?.cancel()
        claimTask = nil
        pauseTransitionTask?.cancel()
        requestedPauseState = false
        presentation.cancelSession(reason: .globalDisable)
        cardWindow.forceHide()
        catWindow.resetToSleeping()
        deferredExternalUpdate = nil
        deferredExternalDisappearance = nil
        dismissingNotification = nil
        guard disableCleanupTask == nil else { return }
        disableCleanupTask = Task { [weak self] in
            guard let self else { return }
            let completion = await queue.completeCurrent(policy: .leavePendingForLater)
            guard !Task.isCancelled else {
                disableCleanupTask = nil
                return
            }
            _ = observeQueueRevision(completion.revision)
            projectNoCurrent(revision: completion.revision)
            let pause = await queue.setPaused(false)
            guard !Task.isCancelled else {
                disableCleanupTask = nil
                return
            }
            _ = observeQueueRevision(pause.revision)
            requestedPauseState = false
            isPaused = false
            isPauseTransitioning = false
            pauseTransitionTask = nil
            let recovery = machine.recoverToSleeping()
            catState = recovery.safeState
            disableCleanupTask = nil
            if settings.preferences.enabled { beginFlowIfNeeded() }
        }
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
                    if outcome == .permissionRequired {
                        systemNotificationAccess.sourceDidLosePermission()
                        cancelActiveExternalSession(
                            reason: .permissionLoss, context: "Accessibility permission loss"
                        )
                        clearExternalNotifications()
                    }
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

    private func cancelActiveExternalSession(
        reason: PresentationCancellationReason,
        context: String
    ) {
        guard current?.externalIdentity != nil, !isRecovering else { return }
        presentation.cancelSession(reason: reason)
        cardWindow.forceHide()
        catWindow.cancelVisualWork()
        scheduleRecovery(context: context)
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
                deferredExternalDisappearance = nil
                deferredExternalUpdate = nil
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
        guard notification.externalIdentity != nil else { return }
        guard externalLifecycleIsStable else {
            if deferredExternalUpdate?.revision ?? 0 <= revision,
               notification.id == current?.id {
                deferredExternalUpdate = .init(notification: notification, revision: revision)
                if let id = presentation.activeSessionID {
                    presentation.deferExternalUpdate(notificationID: notification.id, for: id)
                }
            }
            return
        }
        guard current?.id == notification.id else {
            failQueueReconciliation(context: "external-update identity mismatch")
            return
        }
        deferredExternalUpdate = nil
        if let id = presentation.activeSessionID {
            _ = presentation.replaceContent(for: id, transientDuration: transientDuration(of: notification))
            presentation.clearDeferredExternalLifecycle(for: id)
        }
        projectCurrent(notification, revision: revision)
        startFlow(with: .notificationUpdated)
    }

    private func handleExternalDisappearance(_ identity: ExternalNotificationIdentity) {
        Task { await applyExternalMutation(await queue.removeExternal(identity)) }
    }

    private func dismissSourceCurrent(_ notification: DockCatNotification, revision: NotificationQueueRevision) {
        guard notification.externalIdentity != nil else { return }
        guard externalLifecycleIsStable else {
            if deferredExternalDisappearance?.revision ?? 0 <= revision,
               notification.id == current?.id {
                deferredExternalDisappearance = .init(notification: notification, revision: revision)
                if let id = presentation.activeSessionID {
                    presentation.deferExternalDisappearance(for: id)
                }
            }
            deferredExternalUpdate = nil
            return
        }
        guard current?.id == notification.id else {
            failQueueReconciliation(context: "external-removal identity mismatch")
            return
        }
        deferredExternalDisappearance = nil
        deferredExternalUpdate = nil
        dismissingNotification = notification
        projectNoCurrent(revision: revision)
        startDismissal(with: .sourceDisappeared, cause: .sourceDisappearance)
    }

    /// Applies lifecycle work that arrived while wake/travel/card animation owned the flow.
    /// Disappearance wins over an update because its queue item has already been removed.
    private func applyDeferredExternalLifecycle() {
        guard !presentation.hasChoreographyTask, machine.state == .waitingForDismissal,
              current?.externalIdentity != nil else { return }
        if let removal = deferredExternalDisappearance,
           removal.notification.id == current?.id {
            dismissSourceCurrent(removal.notification, revision: removal.revision)
        } else if let update = deferredExternalUpdate,
                  update.notification.id == current?.id {
            replaceUpdatedCurrent(update.notification, revision: update.revision)
        }
    }

    func receive(url: URL) {
        do { submit(try URLSchemeParser(defaultDuration: settings.preferences.defaultTransientDuration).parse(url)) }
        catch { logger.error("URL notification rejected: \(String(describing: error), privacy: .public)") }
    }

    func refreshPlacement() { reposition() }

    func setPaused(_ paused: Bool) {
        guard settings.preferences.enabled, disableCleanupTask == nil else { return }
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

            if !presentation.hasChoreographyTask, deferredExternalDisappearance == nil,
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
                if let sessionID = presentation.activeSessionID {
                    if outcome.isPaused {
                        await presentation.pause(for: sessionID)
                    } else {
                        await presentation.resume(for: sessionID, onExpiry: transientDidExpire)
                    }
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
        startDismissal(with: .userDismissed, cause: .userClose)
    }

    private func beginFlowIfNeeded() {
        guard settings.preferences.enabled, lastValidPlacement != nil,
              disableCleanupTask == nil,
              claimTask == nil, !presentation.hasChoreographyTask,
              current == nil, !isPaused, !isPauseTransitioning,
              !isRecovering else { return }
        claimTask = Task { [weak self] in
            guard let self else { return }
            let decision = await queue.claimNext()
            guard !Task.isCancelled else { claimTask = nil; return }
            let shouldStart = await applyClaim(decision)
            claimTask = nil
            guard shouldStart else {
                // A stale idle result can be superseded by a pending enqueue while this
                // task owns the claim slot. Retry after releasing the slot so it is not
                // left stranded.
                beginFlowIfNeeded()
                return
            }
            guard await reconcileQueueProjection(context: "claim") else { return }
            startFlow(with: .notificationAvailable)
        }
    }

    private func applyClaim(_ decision: DockCatCore.NotificationQueue.ClaimResult) async -> Bool {
        if !observeQueueRevision(decision.revision) {
            let snapshot = await queue.snapshot()
            guard !Task.isCancelled else { return false }
            _ = observeQueueRevision(snapshot.revision)
            switch decision {
            case .promoted(let notification, _), .current(let notification, _):
                guard snapshot.currentID == notification.id else { return false }
            case .paused, .idle:
                return false
            }
        }
        switch decision {
        case .promoted(let notification, let revision), .current(let notification, let revision):
            projectCurrent(notification, revision: revision)
            startPresentationSession(for: notification, phase: .waking)
            return true
        case .paused, .idle:
            return false
        }
    }

    private func continueFlowIfNeeded() {
        guard !presentation.hasChoreographyTask,
              !isPaused, !isPauseTransitioning, !isRecovering else { return }
        switch presentation.activePhase {
        case .presentingCard:
            startEffectFlow(.presentInitialCard)
        case .replacingCard:
            startEffectFlow(.replaceActiveCard)
        case .dismissingCard:
            startEffectFlow(.dismissExpandedCard)
        default:
            beginFlowIfNeeded()
        }
    }

    private func startEffectFlow(_ effect: CatCoordinatorEffect) {
        guard let sessionID = presentation.activeSessionID else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            let outcome = await execute(effect)
            switch CatEffectChainPolicy.action(after: outcome) {
            case .submit(let event): await process(startingWith: event)
            case .recover: scheduleRecovery(afterEffect: effect)
            case .stop: break
            }
            await flowFinished(sessionID: sessionID)
        }
        presentation.register(task, as: .choreography, for: sessionID)
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
            return await runCatEffect(.wake, phase: .waking)
        case .pickUpCard:
            return await runCatEffect(.pickUp, phase: .pickingUp)
        case .travelToPresentation:
            return await runCatEffect(.walkToPresentation, phase: .travellingToPresentation)
        case .presentInitialCard:
            guard let item = current, let sessionID = presentation.activeSessionID,
                  presentation.beginPhase(.presentingCard, for: sessionID) else { return failClosed(effect) }
            let revision = presentation.snapshot()?.contentRevision
            catWindow.prepareHandoffPose()
            let result = await cardWindow.present(
                notification: item,
                preferences: settings.preferences,
                from: catWindow.handoffSourceRect(),
                reducedMotion: settings.effectiveReducedMotion,
                sessionID: sessionID
            )
            guard PresentationChoreography.shouldAcceptPresentationCompletion(result),
                  !Task.isCancelled,
                  presentation.validate(
                    sessionID, notificationID: item.id, phase: .presentingCard,
                    contentRevision: revision
                  ) == .valid else {
                return handleExpectedInterruption(item: item, state: .presenting)
            }
            return .completed(nextEvent: .cardPresented)
        case .enterWaitingState:
            catWindow.completeHandoffPose()
            guard let sessionID = presentation.activeSessionID else { return failClosed(effect) }
            await presentation.cardPresented(for: sessionID, onExpiry: transientDidExpire)
            return .completed(nextEvent: nil)
        case .replaceActiveCard:
            guard let item = current, let sessionID = presentation.activeSessionID,
                  presentation.beginPhase(.replacingCard, for: sessionID) else { return failClosed(effect) }
            let revision = presentation.snapshot()?.contentRevision
            let result = await cardWindow.replace(
                notification: item,
                preferences: settings.preferences,
                reducedMotion: settings.effectiveReducedMotion,
                sessionID: sessionID
            )
            guard result == .completed, !Task.isCancelled,
                  presentation.validate(
                    sessionID, notificationID: item.id, phase: .replacingCard,
                    contentRevision: revision
                  ) == .valid else {
                return handleExpectedInterruption(item: item, state: .presenting)
            }
            return .completed(nextEvent: .cardPresented)
        case .selectNextQueueAction:
            return await selectNextQueueAction(effect: effect)
        case .dismissExpandedCard:
            guard let item = dismissingNotification, let sessionID = presentation.activeSessionID,
                  presentation.beginPhase(.dismissingCard, for: sessionID) else { return failClosed(effect) }
            let result = await cardWindow.dismissActive(
                toward: catWindow.handoffSourceRect(),
                reducedMotion: settings.effectiveReducedMotion,
                sessionID: sessionID
            )
            guard result == .completed, !Task.isCancelled,
                  presentation.validate(
                    sessionID, notificationID: item.id, phase: .dismissingCard,
                    allowDismissing: true
                  ) == .valid else {
                return handleExpectedInterruption(item: item, state: .dismissingCard)
            }
            dismissingNotification = nil
            catWindow.hideCarriedCard()
            return .completed(nextEvent: .cardDismissed)
        case .travelHome:
            return await runCatEffect(.walkHome, phase: .travellingHome, allowDismissing: true)
        case .settleToSleep:
            return await runCatEffect(.settle, phase: .settling, allowDismissing: true)
        case .pauseVisualWork, .resumePriorWork:
            preconditionFailure("State-control effects are handled before the async effect switch")
        case .none:
            return .completed(nextEvent: nil)
        }
    }

    private func runCatEffect(
        _ animation: CatAnimation,
        phase: PresentationPhase,
        allowDismissing: Bool = false
    ) async -> CatEffectExecutionOutcome {
        guard let sessionID = presentation.activeSessionID,
              presentation.beginPhase(phase, for: sessionID) else { return .failed }
        let notificationID = current?.id ?? dismissingNotification?.id
        let result = await catWindow.animate(
            animation,
            speed: settings.preferences.animationSpeed,
            reducedMotion: settings.effectiveReducedMotion,
            sessionID: sessionID
        )
        guard result == .completed, !Task.isCancelled,
              presentation.validate(
                sessionID, notificationID: notificationID, phase: phase,
                allowDismissing: allowDismissing
              ) == .valid else { return .cancelled }
        return .completed(nextEvent: .animationCompleted)
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
            startPresentationSession(for: next, phase: .replacingCard)
            startFlow(with: .nextNotificationAvailable)
            return .cancelled
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
            deferredExternalUpdate = nil
            deferredExternalDisappearance = nil
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
            startPresentationSession(for: next, phase: .replacingCard)
            startFlow(with: .nextNotificationAvailable)
            return .cancelled
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
            if presentation.hasChoreographyTask { return }
        }
        continueFlowIfNeeded()
    }

    private func handleExpectedInterruption(
        item: DockCatNotification,
        state expectedState: CatState
    ) -> CatEffectExecutionOutcome {
        let ownedID = current?.id ?? dismissingNotification?.id
        guard !Task.isCancelled, ownedID == item.id,
              isPaused || machine.state == expectedState else { return .cancelled }
        return .cancelled
    }

    private func failClosed(_ effect: CatCoordinatorEffect) -> CatEffectExecutionOutcome {
        logger.fault("Cat coordinator effect failed effect=\(effect.rawValue, privacy: .public) recovery=true")
        return .failed
    }

    private func flowFinished(sessionID: PresentationSessionID) async {
        presentation.clearTask(.choreography, for: sessionID)
        guard presentation.validate(sessionID, allowDismissing: true) == .valid else { return }
        guard !Task.isCancelled, !isPaused, !isRecovering else { return }
        if machine.state == .waitingForDismissal {
            applyDeferredExternalLifecycle()
        } else if machine.state == .sleeping {
            presentation.finishSession(sessionID)
            beginFlowIfNeeded()
        }
    }

    private func transientDidExpire(_ sessionID: PresentationSessionID) {
        guard presentation.validate(sessionID, phase: .waitingForDismissal) == .valid else { return }
        startDismissal(with: .transientExpired, cause: .transientExpiry)
    }

    private func startDismissal(with event: CatEvent, cause: DismissalCause) {
        guard !presentation.hasChoreographyTask, !isPaused, !isPauseTransitioning,
              !isRecovering, machine.state == .waitingForDismissal,
              let sessionID = presentation.activeSessionID else { return }
        guard case .began(let winner) = presentation.beginDismissal(
            sessionID: sessionID, cause: cause
        ) else { return }
        logger.info(
            "Presentation dismissal generation=\(sessionID.generation, privacy: .public) cause=\(winner.rawValue, privacy: .public)"
        )
        startFlow(with: event)
    }

    private func startFlow(with event: CatEvent) {
        guard !presentation.hasChoreographyTask, !isRecovering,
              let sessionID = presentation.activeSessionID else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            await process(startingWith: event)
            await flowFinished(sessionID: sessionID)
        }
        presentation.register(task, as: .choreography, for: sessionID)
    }

    private func startPresentationSession(
        for notification: DockCatNotification,
        phase: PresentationPhase
    ) {
        deferredExternalUpdate = nil
        deferredExternalDisappearance = nil
        _ = presentation.startSession(
            notificationID: notification.id,
            transientDuration: transientDuration(of: notification),
            phase: phase
        )
    }

    private func transientDuration(of notification: DockCatNotification) -> Duration? {
        guard case .transient(let seconds) = notification.presentation else { return nil }
        return .seconds(seconds)
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
        let sessionID = presentation.activeSessionID
        pauseTransitionTask?.cancel()
        cardWindow.cancelPresentationAnimation()
        catWindow.cancelVisualWork()
        cardWindow.forceHide()
        if let sessionID {
            await presentation.cancelTaskAndWait(.choreography, for: sessionID)
        }
        presentation.cancelSession(reason: .recovery)
        // Cancellation unblocks continuations first. This final reset runs only after the
        // old flow can no longer overwrite the sleeping pose or card visibility.
        catWindow.resetToSleeping()
        cardWindow.forceHide()
        deferredExternalUpdate = nil
        deferredExternalDisappearance = nil
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
        logger.fault(
            "Cat coordinator recovered previous=\(recovery.previousState.rawValue, privacy: .public) safe=\(recovery.safeState.rawValue, privacy: .public) context=\(context, privacy: .public)"
        )
        isRecovering = false
        recoveryGate.recoveryCompleted()
        recoveryTask = nil
        beginFlowIfNeeded()
    }

    /// Coalesces screen notifications and slider ticks into one main-actor refresh using
    /// the newest preferences. The refresh never submits a CatEvent or touches the queue.
    private func reposition() {
        guard placementRefreshTask == nil else { return }
        placementRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.placementRefreshTask = nil
            self.applyNewestPlacement()
        }
    }

    private func applyNewestPlacement() {
        placementRevision &+= 1
        let logicalPlacement = CatLogicalPlacementResolver.resolve(
            catState: machine.state,
            presentationPhase: presentation.activePhase,
            hasChoreographyTask: presentation.hasChoreographyTask,
            isRecovering: isRecovering,
            isEnabled: settings.preferences.enabled
        )

        guard let geometry = locator.locate(preferences: settings.preferences) else {
            let availability = PlacementRefreshPolicy.availabilityAction(
                hasResolvedPlacement: false,
                hasLastValidPlacement: lastValidPlacement != nil
            )
            let retainedLastValid = availability == .retainLastValidPlacement
            logger.info(
                "Placement refresh revision=\(self.placementRevision, privacy: .public) logical=\(logicalPlacement.rawValue, privacy: .public) motionRetargeted=false cardRebased=false fallback=false lastValid=\(retainedLastValid, privacy: .public)"
            )
            return
        }

        let isFirstValidPlacement = lastValidPlacement == nil
        lastValidPlacement = geometry
        let sessionID = presentation.activeSessionID
        let catOutcome = catWindow.updatePlacement(
            geometry, logicalState: logicalPlacement, sessionID: sessionID
        )
        // Cat placement is applied first so a dismiss animation rebases toward the
        // handoff rect derived from the same new presentation transaction.
        let cardOutcome = cardWindow.updatePlacement(
            above: geometry.presentationPoint,
            offset: settings.preferences.cardOffset,
            logicalState: logicalPlacement,
            dismissalSourceRect: catWindow.handoffSourceRect()
        )
        if isFirstValidPlacement {
            // Startup with no screen leaves the overlay unordered. Delivery is gated on
            // this first valid placement, so the reset cannot interrupt active work.
            catWindow.resetToSleeping()
            beginFlowIfNeeded()
        }
        logger.info(
            "Placement refresh revision=\(self.placementRevision, privacy: .public) logical=\(logicalPlacement.rawValue, privacy: .public) oldEdge=\(catOutcome.previousDockEdge.rawValue, privacy: .public) newEdge=\(geometry.edge.rawValue, privacy: .public) motionRetargeted=\(catOutcome.motionWasRetargeted, privacy: .public) cardRebased=\(cardOutcome.animationWasRebased, privacy: .public) fallback=\(geometry.usedDisplayFallback, privacy: .public) lastValid=false"
        )
    }

    private var externalLifecycleIsStable: Bool {
        !presentation.hasChoreographyTask && !isPaused && !isPauseTransitioning && !isRecovering
            && machine.state == .waitingForDismissal
    }

}
