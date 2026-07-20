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
    @Published private(set) var currentPlacement: DockPlacement?
    @Published private var isPlacementCurrentlyResolved = false
    @Published private(set) var isCalibrationPreviewActive = false
    @Published private(set) var effectiveAnimationPreferences: EffectiveAnimationPreferences = .default
    @Published private(set) var runtimeSnapshot = DockCatRuntimeSnapshot(
        mode: .disabled,
        visualMode: .full,
        systemSourceRequested: false
    )
    let settings = SettingsStore()
    let displayCatalog = DisplayCatalog()
    private lazy var systemNotificationSource = SystemNotificationAccessibilitySource(
        dismissalRegistry: accessibilityElementRegistry,
        generatedEventHandler: { [weak self] event, generation in
            self?.receive(sourceEvent: event, generation: generation)
        },
        outcomeHandler: { _ in }
    )
    lazy var systemNotificationAccess: SystemNotificationAccessController = {
        let controller = SystemNotificationAccessController(
            enabled: settings.preferences.systemNotificationsEnabled,
            runtimeAllowed: false,
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
    private let calibrationPreview = DockCalibrationPreviewController()
    private let presentation = PresentationSessionCoordinator()
    private var claimTask: Task<Void, Never>?
    private var lifecycleTask: Task<Void, Never>?
    private var presentationCancellationTasks: [Task<Void, Never>] = []
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
    private var placementRefreshTask: Task<Void, Never>?
    private var visualPreferenceRefreshTask: Task<Void, Never>?
    private var placementRevision: UInt64 = 0
    private var lastValidPlacement: DockPlacement?
    private lazy var runtimeLifecycle = DockCatRuntimeLifecycle(
        initiallyEnabled: settings.preferences.enabled,
        visualMode: settings.effectiveAnimationPreferences.mode,
        systemSourceRequested: settings.preferences.systemNotificationsEnabled
    )
    private var desiredEnabled = false
    private var runtimeGeneration: UInt64 = 0
    private var bootstrapGuard = ApplicationBootstrapGuard()
    private var startupNotificationBuffer = StartupNotificationBuffer()
    private let logger = Logger(subsystem: "com.example.DockCat", category: "AppState")

    var runtimeMode: DockCatRuntimeMode { runtimeSnapshot.mode }
    var canMutatePause: Bool {
        runtimeMode.acceptsPauseMutation && !isPauseTransitioning && lifecycleTask == nil
    }
    var canSubmitNotifications: Bool { runtimeMode.acceptsSubmissions }

    func start() {
        guard bootstrapGuard.beginIfNeeded() else {
            logger.error("Bootstrap duplicate-start rejected")
            return
        }
        desiredEnabled = settings.preferences.enabled
        runtimeSnapshot = runtimeLifecycle.snapshot
        settings.accessibilityDisplayOptions.onChange = { [weak self] _ in
            self?.scheduleVisualPreferenceRefresh()
        }
        settings.accessibilityDisplayOptions.start()
        applyNewestVisualPreferences()
        systemNotificationAccess.setRuntimeAllowed(false)
        applyNewestPlacement()
        cardWindow.onDismiss = { [weak self] in self?.dismissCurrent() }
        displayCatalog.onChange = { [weak self] in
            self?.objectWillChange.send()
            self?.reposition()
        }
        if desiredEnabled {
            scheduleLifecycleTransaction()
        } else {
            catWindow.hideOverlay()
            cardWindow.forceHide()
            stopCalibrationPreview()
        }
    }

    func stop() async {
        guard runtimeMode != .shuttingDown else { return }
        _ = applyRuntime(.shutdown)
        desiredEnabled = false
        runtimeGeneration &+= 1
        let activeLifecycle = lifecycleTask
        lifecycleTask = nil
        activeLifecycle?.cancel()
        await activeLifecycle?.value
        systemNotificationAccess.setRuntimeAllowed(false)
        systemNotificationAccess.shutdown()
        await systemNotificationPipeline.deactivate()
        await stopLifecycleReconciliationAndWait()
        let claim = claimTask
        claimTask = nil
        claim?.cancel()
        await claim?.value
        let pause = pauseTransitionTask
        pauseTransitionTask = nil
        pause?.cancel()
        await pause?.value
        let recovery = recoveryTask
        recoveryTask = nil
        recovery?.cancel()
        await recovery?.value
        let presentationTasks = presentationCancellationTasks
            + presentation.cancelSession(reason: .appShutdown)
        presentationCancellationTasks.removeAll()
        presentationTasks.forEach { $0.cancel() }
        cardWindow.cancelPresentationAnimation()
        catWindow.cancelVisualWork()
        cardWindow.forceHide()
        catWindow.hideOverlay()
        for task in presentationTasks { await task.value }
        let clear = await queue.clearForGlobalDisable()
        _ = observeQueueRevision(clear.revision)
        projectNoCurrent(revision: clear.revision)
        requestedPauseState = false
        isPaused = false
        isPauseTransitioning = false
        deferredExternalUpdate = nil
        deferredExternalDisappearance = nil
        dismissingNotification = nil
        startupNotificationBuffer.removeAll()
        isRecovering = false
        recoveryGate.recoveryCompleted()
        let machineRecovery = machine.recoverToSleeping()
        catState = machineRecovery.safeState
        catWindow.resetVisualStateWhileHidden()
        placementRefreshTask?.cancel()
        placementRefreshTask = nil
        visualPreferenceRefreshTask?.cancel()
        visualPreferenceRefreshTask = nil
        settings.accessibilityDisplayOptions.stop()
        stopCalibrationPreview()
        displayCatalog.stop()
    }

    private func clearExternalNotifications() {
        guard runtimeMode.acceptsSubmissions else { return }
        let generation = runtimeGeneration
        Task {
            let outcomes = await systemNotificationPipeline.sourceStopped(
                runtimeGeneration: generation
            )
            for outcome in outcomes { await applyExternalMutation(outcome.queueMutation) }
        }
    }

    func setSystemNotificationsEnabled(_ enabled: Bool) {
        settings.preferences.systemNotificationsEnabled = enabled
        _ = applyRuntime(.updateSystemSourceRequested(enabled))
        if !enabled {
            cancelActiveExternalSession(reason: .sourceShutdown, context: "source disabled")
            clearExternalNotifications()
        }
        systemNotificationAccess.setEnabled(enabled)
    }

    func setDockCatEnabled(_ enabled: Bool) {
        guard desiredEnabled != enabled || settings.preferences.enabled != enabled else { return }
        settings.preferences.enabled = enabled
        desiredEnabled = enabled
        if !enabled { startupNotificationBuffer.removeAll() }
        if !enabled && (runtimeMode == .running || runtimeMode == .deliveryPaused) {
            _ = applyRuntime(.beginDisabling)
            runtimeGeneration &+= 1
            systemNotificationAccess.setRuntimeAllowed(false)
            stopCalibrationPreview()
            claimTask?.cancel()
            pauseTransitionTask?.cancel()
            presentationCancellationTasks = presentation.cancelSession(reason: .globalDisable)
            cardWindow.forceHide()
            catWindow.hideOverlay()
        } else if enabled, runtimeMode == .disabled, lifecycleTask == nil {
            _ = applyRuntime(.beginEnabling)
        }
        scheduleLifecycleTransaction()
    }

    private func scheduleLifecycleTransaction() {
        guard lifecycleTask == nil, runtimeMode != .shuttingDown else { return }
        lifecycleTask = Task { [weak self] in
            await self?.drainLifecycleRequests()
        }
    }

    private func drainLifecycleRequests() async {
        while !Task.isCancelled, runtimeMode != .shuttingDown {
            if desiredEnabled {
                if runtimeMode == .disabled { _ = applyRuntime(.beginEnabling) }
                guard runtimeMode == .enabling else { break }
                await performEnableTransaction()
            } else {
                if runtimeMode == .running || runtimeMode == .deliveryPaused || runtimeMode == .enabling {
                    _ = applyRuntime(.beginDisabling)
                    runtimeGeneration &+= 1
                    systemNotificationAccess.setRuntimeAllowed(false)
                }
                guard runtimeMode == .disabling else { break }
                await performDisableTransaction()
            }
        }
        lifecycleTask = nil
        if runtimeMode == .running { beginFlowIfNeeded() }
        if desiredEnabled != runtimeMode.isEnabled, runtimeMode != .shuttingDown {
            scheduleLifecycleTransaction()
        }
    }

    private func performDisableTransaction() async {
        stopCalibrationPreview()
        await systemNotificationPipeline.deactivate()
        await stopLifecycleReconciliationAndWait()
        let claim = claimTask
        claimTask = nil
        claim?.cancel()
        await claim?.value
        let pause = pauseTransitionTask
        pauseTransitionTask = nil
        pause?.cancel()
        await pause?.value
        let cancelledRecoveryTask = self.recoveryTask
        self.recoveryTask = nil
        cancelledRecoveryTask?.cancel()
        await cancelledRecoveryTask?.value
        if presentationCancellationTasks.isEmpty {
            await presentation.cancelSessionAndWait(reason: .globalDisable)
        } else {
            let tasks = presentationCancellationTasks
            presentationCancellationTasks.removeAll()
            for task in tasks { await task.value }
        }
        cardWindow.cancelPresentationAnimation()
        catWindow.cancelVisualWork()
        cardWindow.forceHide()
        catWindow.hideOverlay()
        let clear = await queue.clearForGlobalDisable()
        guard runtimeMode != .shuttingDown else { return }
        _ = observeQueueRevision(clear.revision)
        projectNoCurrent(revision: clear.revision)
        deferredExternalUpdate = nil
        deferredExternalDisappearance = nil
        dismissingNotification = nil
        requestedPauseState = false
        isPaused = false
        isPauseTransitioning = false
        isRecovering = false
        recoveryGate.recoveryCompleted()
        let recovery = machine.recoverToSleeping()
        catState = recovery.safeState
        catWindow.resetVisualStateWhileHidden()
        logger.info(
            "Queue cleared current=\(clear.removedCurrentID != nil, privacy: .public) pending=\(clear.removedPendingCount, privacy: .public) revision=\(clear.revision, privacy: .public)"
        )
        _ = applyRuntime(.finishDisabling)
    }

    private func performEnableTransaction() async {
        runtimeGeneration &+= 1
        let generation = runtimeGeneration
        systemNotificationAccess.setRuntimeAllowed(false)
        stopLifecycleReconciliation()
        let clear = await queue.clearForGlobalDisable()
        _ = observeQueueRevision(clear.revision)
        projectNoCurrent(revision: clear.revision)
        requestedPauseState = false
        isPaused = false
        isPauseTransitioning = false
        deferredExternalUpdate = nil
        deferredExternalDisappearance = nil
        dismissingNotification = nil
        let recovery = machine.recoverToSleeping()
        catState = recovery.safeState
        applyNewestVisualPreferences()
        applyNewestPlacement()
        catWindow.resetVisualStateWhileHidden()
        guard desiredEnabled, runtimeMode == .enabling, !Task.isCancelled else { return }
        if isPlacementCurrentlyResolved, let placement = currentPlacement {
            catWindow.showSleeping(using: placement)
            logger.info("Cat overlay shown generation=\(generation, privacy: .public)")
        }
        await queue.activateRuntimeGeneration(generation)
        await systemNotificationPipeline.activate(runtimeGeneration: generation)
        systemNotificationAccess.setRuntimeAllowed(true)
        startLifecycleReconciliation(generation: generation)
        guard runtimeMode == .enabling, !Task.isCancelled else { return }
        _ = applyRuntime(.finishEnabling)
        enqueue(startupNotificationBuffer.drainIfRunning(runtimeMode: runtimeMode))
        beginFlowIfNeeded()
    }

    @discardableResult
    private func applyRuntime(_ action: DockCatRuntimeAction) -> DockCatRuntimeTransition? {
        let result = runtimeLifecycle.apply(action)
        guard case .accepted(let transition) = result else { return nil }
        runtimeSnapshot = transition.next
        logger.info(
            "Runtime transition previous=\(transition.previous.mode.rawValue, privacy: .public) next=\(transition.next.mode.rawValue, privacy: .public) generation=\(self.runtimeGeneration, privacy: .public)"
        )
        return transition
    }

    private func startLifecycleReconciliation(generation: UInt64) {
        guard lifecycleReconciliationTask == nil else { return }
        lifecycleReconciliationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self,
                      self.runtimeGeneration == generation,
                      self.runtimeMode.acceptsSubmissions,
                      self.systemNotificationAccess.acceptsCallback(
                        generation: self.systemNotificationAccess.generation
                      ) else { return }
                let outcomes = await self.systemNotificationPipeline.reconcile(
                    runtimeGeneration: generation
                )
                guard self.runtimeGeneration == generation else { return }
                for outcome in outcomes { await self.applyExternalMutation(outcome.queueMutation) }
            }
        }
    }

    private func stopLifecycleReconciliation() {
        lifecycleReconciliationTask?.cancel()
        lifecycleReconciliationTask = nil
    }

    private func stopLifecycleReconciliationAndWait() async {
        let task = lifecycleReconciliationTask
        lifecycleReconciliationTask = nil
        task?.cancel()
        await task?.value
    }

    func sendTest(persistent: Bool = false) {
        submit(.init(sourceName: "DockCat", title: persistent ? "Persistent alert" : "Hello from DockCat",
                     message: persistent ? "Close this card when you are ready." : "The cat delivered this test notification.",
                     presentation: persistent ? .persistent : .transient(duration: settings.preferences.defaultTransientDuration)))
    }

    func submit(_ notification: DockCatNotification) {
        if startupNotificationBuffer.deferIfEnabling(
            notification, runtimeMode: runtimeMode
        ) {
            logger.info(
                "Notification deferred during startup: \(notification.id, privacy: .public), pending: \(self.startupNotificationBuffer.count, privacy: .public)"
            )
            return
        }
        guard runtimeMode.acceptsSubmissions else { return }
        enqueue([notification])
    }

    private func enqueue(_ notifications: [DockCatNotification]) {
        guard !notifications.isEmpty else { return }
        let generation = runtimeGeneration
        Task {
            observeQueueRevision((await queue.setLimit(
                settings.preferences.queueLimit, runtimeGeneration: generation
            )).revision)
            var acceptedAny = false
            for notification in notifications {
                let result = await queue.enqueue(
                    notification, runtimeGeneration: generation
                )
                logger.info("Notification received: \(notification.id, privacy: .public), result: \(String(describing: result), privacy: .public)")
                _ = observeQueueRevision(result.revision)
                acceptedAny = acceptedAny || result.wasAccepted
            }
            guard acceptedAny, generation == runtimeGeneration,
                  runtimeMode.acceptsSubmissions else { return }
            beginFlowIfNeeded()
        }
    }

    func receive(sourceEvent: NotificationSourceEvent, generation: UInt64) {
        guard runtimeMode.acceptsSubmissions,
              systemNotificationAccess.acceptsCallback(generation: generation) else {
            logger.info("Stale source callback rejected category=runtime-generation")
            return
        }
        switch sourceEvent {
        case .notification(let notification), .oneShot(let notification): submit(notification)
        case .appeared(let external): handleExternalAppearance(external.notification)
        case .updated(let external): handleExternalUpdate(external.notification)
        case .disappeared(let identity): handleExternalDisappearance(identity)
        case .accessibilitySnapshot(let snapshot):
            let applicationGeneration = runtimeGeneration
            Task {
                observeQueueRevision((await queue.setLimit(
                    settings.preferences.queueLimit,
                    runtimeGeneration: applicationGeneration
                )).revision)
                let result = await systemNotificationPipeline.ingest(
                    snapshot, transientDuration: settings.preferences.defaultTransientDuration,
                    runtimeGeneration: applicationGeneration
                )
                logger.info("Accessibility notification result=\(String(describing: result.kind), privacy: .public)")
                if applicationGeneration == runtimeGeneration,
                   runtimeMode.acceptsSubmissions,
                   systemNotificationAccess.acceptsCallback(generation: generation),
                   settings.preferences.isNativeBannerDismissalEnabled,
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
        guard runtimeMode.acceptsSubmissions else { return }
        let generation = runtimeGeneration
        Task {
            observeQueueRevision((await queue.setLimit(
                settings.preferences.queueLimit, runtimeGeneration: generation
            )).revision)
            await applyExternalMutation(await queue.enqueueAppeared(
                notification, runtimeGeneration: generation
            ))
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
        guard runtimeMode.acceptsSubmissions else { return }
        let generation = runtimeGeneration
        Task { await applyExternalMutation(await queue.updateExternal(
            notification, runtimeGeneration: generation
        )) }
    }

    private func applyExternalMutation(
        _ mutation: DockCatCore.NotificationQueue.ExternalMutationResult?
    ) async {
        guard let mutation else { return }
        guard runtimeMode.acceptsSubmissions else {
            logger.info("Stale source callback rejected category=runtime-mode")
            return
        }
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
        guard runtimeMode.acceptsSubmissions else { return }
        let generation = runtimeGeneration
        Task { await applyExternalMutation(await queue.removeExternal(
            identity, runtimeGeneration: generation
        )) }
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

    func refreshPlacement() { reposition() }

    func setCatScale(_ value: Double) {
        settings.preferences.catScale = EffectiveAnimationPreferences.clampedCatScale(value)
        scheduleVisualPreferenceRefresh()
    }

    func setIdleAnimation(_ enabled: Bool) {
        settings.preferences.idleAnimation = enabled
        scheduleVisualPreferenceRefresh()
    }

    func setDisableWalking(_ disabled: Bool) {
        settings.preferences.disableWalking = disabled
        scheduleVisualPreferenceRefresh()
    }

    func setPauseAnimations(_ paused: Bool) {
        settings.preferences.pauseAnimations = paused
        scheduleVisualPreferenceRefresh()
    }

    func setAppReducedMotion(_ reduced: Bool) {
        settings.preferences.reducedMotion = reduced
        scheduleVisualPreferenceRefresh()
    }

    func setAnimationSpeed(_ speed: Double) {
        settings.preferences.animationSpeed = EffectiveAnimationPreferences.clampedSpeed(speed)
        scheduleVisualPreferenceRefresh()
    }

    /// Coalesces rapid slider ticks while persisting every newest value before runtime use.
    private func scheduleVisualPreferenceRefresh() {
        guard visualPreferenceRefreshTask == nil else { return }
        visualPreferenceRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.visualPreferenceRefreshTask = nil
            self.applyNewestVisualPreferences()
        }
    }

    private func applyNewestVisualPreferences() {
        let previous = effectiveAnimationPreferences
        let newest = settings.effectiveAnimationPreferences
        effectiveAnimationPreferences = newest
        _ = applyRuntime(.updateVisualMode(newest.mode))
        let geometryChanged = catWindow.applyVisualPreferences(newest)
        cardWindow.applyVisualPreferences(newest)
        if geometryChanged { reposition() }
        guard previous != newest else { return }
        logger.info(
            "Visual preferences mode=\(newest.mode.rawValue, privacy: .public) appReduced=\(newest.appReducedMotion, privacy: .public) systemReduced=\(newest.systemReducedMotion, privacy: .public) idle=\(newest.idleAnimationEnabled, privacy: .public) scale=\(newest.catScale, privacy: .public) overlayWidth=\(CatOverlayGeometry(scale: newest.catScale).panelSize.width, privacy: .public) overlayHeight=\(CatOverlayGeometry(scale: newest.catScale).panelSize.height, privacy: .public) rebased=\(geometryChanged, privacy: .public)"
        )
    }

    var isCalibrationAvailable: Bool {
        isPlacementCurrentlyResolved
            && currentPlacement?.requestedDisplayAvailable == true
    }

    func startCalibrationPreview() {
        guard runtimeMode.acceptsSubmissions,
              isCalibrationAvailable,
              let placement = currentPlacement else { return }
        calibrationPreview.start(with: placement)
        isCalibrationPreviewActive = true
    }

    func stopCalibrationPreview() {
        calibrationPreview.stop()
        isCalibrationPreviewActive = false
    }

    func setPaused(_ paused: Bool) {
        guard runtimeMode.acceptsPauseMutation, lifecycleTask == nil else { return }
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
            guard !Task.isCancelled, !isRecovering,
                  runtimeMode.acceptsPauseMutation else { break }
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
                _ = applyRuntime(outcome.isPaused ? .pauseDelivery : .resumeDelivery)
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
        guard runtimeMode.permitsQueueClaims, isPlacementCurrentlyResolved,
              lifecycleTask == nil,
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
                visualPreferences: effectiveAnimationPreferences,
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
                visualPreferences: effectiveAnimationPreferences,
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
                visualPreferences: effectiveAnimationPreferences,
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
            preferences: effectiveAnimationPreferences,
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
            // A specifically selected display may have reconnected while presentation
            // was active. Sleeping is the documented safe restoration boundary.
            reposition()
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
        guard runtimeMode.acceptsSubmissions else { return }
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
        if runtimeMode.acceptsSubmissions {
            catWindow.resetToSleeping()
        } else {
            catWindow.resetVisualStateWhileHidden()
        }
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
        if runtimeMode.acceptsSubmissions { beginFlowIfNeeded() }
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
            isEnabled: runtimeMode.isEnabled
        )

        guard let geometry = locator.locate(
            preferences: settings.preferences,
            catalog: displayCatalog,
            safeToRestoreSpecific: PlacementRefreshPolicy.canRestoreSpecificDisplay(
                catState: machine.state
            )
        ) else {
            stopCalibrationPreview()
            isPlacementCurrentlyResolved = false
            if runtimeMode == .enabling || runtimeMode == .running {
                catWindow.hideOverlay()
            }
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
        currentPlacement = geometry
        isPlacementCurrentlyResolved = true
        if let migrated = geometry.migratedSelection,
           migrated != settings.preferences.displaySelection {
            settings.preferences.displaySelection = migrated
        }
        if geometry.requestedDisplayAvailable {
            calibrationPreview.update(geometry)
        } else {
            stopCalibrationPreview()
        }
        let sessionID = presentation.activeSessionID
        let catOutcome = catWindow.updatePlacement(
            geometry, logicalState: logicalPlacement, sessionID: sessionID
        )
        // Card exclusion protects the new destination even when outbound travel preserves
        // the panel's old origin. Dismissal rebasing separately follows the live cat rect.
        let destinationExclusionFrame = catWindow.presentationExclusionFrame()
        let liveHandoffRect = catWindow.handoffSourceRect()
        let cardOutcome = cardWindow.updatePlacementContext(
            CardPlacementContext(
                presentationAnchor: geometry.presentationPoint,
                dockEdge: geometry.edge,
                visibleScreenFrame: geometry.visibleScreenFrame,
                catExclusionFrame: destinationExclusionFrame,
                offset: settings.preferences.cardOffset,
                placementRevision: placementRevision
            ),
            logicalState: logicalPlacement,
            dismissalSourceRect: liveHandoffRect
        )
        if (isFirstValidPlacement || !catWindow.isVisible),
           runtimeMode == .running,
           machine.state == .sleeping,
           presentation.activeSessionID == nil {
            // Startup with no screen leaves the overlay unordered. Delivery is gated on
            // this first valid placement, so the reset cannot interrupt active work.
            catWindow.showSleeping(using: geometry)
            beginFlowIfNeeded()
        }
        logger.info(
            "Placement refresh revision=\(self.placementRevision, privacy: .public) logical=\(logicalPlacement.rawValue, privacy: .public) display=\(geometry.displayIdentity.diagnosticsToken, privacy: .public) oldEdge=\(catOutcome.previousDockEdge.rawValue, privacy: .public) newEdge=\(geometry.edge.rawValue, privacy: .public) confidence=\(geometry.geometryConfidence.rawValue, privacy: .public) calibration=\(!self.settings.preferences.calibration(for: geometry.displayIdentity, edge: geometry.edge).isZero, privacy: .public) motionRetargeted=\(catOutcome.motionWasRetargeted, privacy: .public) cardRebased=\(cardOutcome.animationWasRebased, privacy: .public) fallback=\(geometry.usedDisplayFallback, privacy: .public) lastValid=false"
        )
    }

    private var externalLifecycleIsStable: Bool {
        !presentation.hasChoreographyTask && !isPaused && !isPauseTransitioning && !isRecovering
            && machine.state == .waitingForDismissal
    }

}
