import AppKit
import DockCatCore
import OSLog
import SwiftUI

struct CardPlacementUpdateOutcome {
    let animationWasRebased: Bool
}

struct CardPlacementContext: Equatable {
    let presentationAnchor: CGPoint
    let dockEdge: DockEdge
    let visibleScreenFrame: CGRect
    let catExclusionFrame: CGRect?
    let offset: Double
    let placementRevision: UInt64
}

enum CardLayoutMetrics {
    static let values = CardContentLayoutMetrics.standard
    static let preferredWidth = CGFloat(values.preferredWidth)
    static let minimumWidth = CGFloat(values.minimumUsableWidth)
    static let minimumHeight = CGFloat(values.compactMinimumHeight)
    static let maximumHeight = CGFloat(values.maximumHeight)
    static let screenMargin = CGFloat(values.screenMargin)
}

@MainActor
private final class CardHostingView: NSHostingView<NotificationCardView> {
}

@MainActor
final class CardWindowController: NSObject, NSWindowDelegate {
    private struct OperationID: Equatable {
        let sessionID: PresentationSessionID
        let sequence: UInt64
    }

    private struct PendingAnimation {
        let id: OperationID
        let placementRevision: UInt64
        let continuation: CheckedContinuation<PresentationAnimationResult, Never>
        let cancel: @MainActor () -> Void
    }

    private enum VisualOperation: Equatable {
        case presenting
        case replacing
        case dismissing
    }

    private struct InstalledContent {
        let notification: DockCatNotification
        let preferences: DockCatPreferences
    }

    private struct PendingRegionMeasurement {
        let measurements: CardContentRegionMeasurements
        let notificationID: UUID
        let hostingModelRevision: UInt64
    }

    /// Region changes below this threshold are layout noise, not semantic resizing.
    private static let measurementEpsilon = 0.5

    private let panel = CardOverlayPanel()
    private let interactionCoordinator = CardInteractionCoordinator()
    private let accessibilityAnnouncer: CardAccessibilityAnnouncer
    private let logger = Logger(subsystem: "com.example.DockCat", category: "CardPlacement")
    private var placementContext: CardPlacementContext?
    private var logicalPlacement: CatLogicalPlacement = .home
    private var measuredCardSize = CGSize(
        width: CardLayoutMetrics.preferredWidth,
        height: CardLayoutMetrics.minimumHeight
    )
    private var stableCardFrame: CGRect?
    private var installedContent: InstalledContent?
    private var installedSessionID: PresentationSessionID?
    private var interactionFocusGeneration: UInt64?
    private var keyboardFocusTarget: CardKeyboardTarget?
    private weak var hostingView: CardHostingView?
    private var queueContext: CardQueueContext = .empty
    private var queueContextRevision: NotificationQueueRevision = 0
    private var regionMeasurements = CardContentRegionMeasurements(
        headerHeight: 0,
        titleHeight: 0,
        bodyHeight: 0,
        actionsHeight: 0,
        queueFooterHeight: 0
    )
    private var layoutPlan = CardContentLayoutPlanner.plan(.init(
        availableWidth: CardLayoutMetrics.preferredWidth,
        availableHeight: CardLayoutMetrics.maximumHeight,
        measurements: .init(
            headerHeight: 0, titleHeight: 0, bodyHeight: 0,
            actionsHeight: 0, queueFooterHeight: 0
        )
    ))
    private var hostingModelRevision: UInt64 = 0
    private var pendingRegionMeasurement: PendingRegionMeasurement?
    private var measurementCallbackScheduled = false
    private var operationSequence: UInt64 = 0
    private var currentOperationID: OperationID?
    private var currentVisualOperation: VisualOperation?
    private var currentOperationUsesReducedMotion = false
    private var visualPreferences: EffectiveAnimationPreferences = .default
    private var accessibilityDisplayOptions: AccessibilityDisplayOptions = .standard
    private var dismissalSourceRect: CGRect?
    private var pendingAnimation: PendingAnimation?
    private var suppressCloseCallback = false
    var onDismiss: (() -> Void)?
    var validateInteractionSession: ((PresentationSessionID) -> Bool)?

    override convenience init() {
        self.init(accessibilityAnnouncementDelivery: AppKitCardAccessibilityAnnouncementDelivery())
    }

    init(accessibilityAnnouncementDelivery: any CardAccessibilityAnnouncementDelivering) {
        accessibilityAnnouncer = CardAccessibilityAnnouncer(
            delivery: accessibilityAnnouncementDelivery
        )
        super.init()
        panel.delegate = self
        interactionCoordinator.onDismissRequested = { [weak self] in
            self?.onDismiss?()
        }
        panel.onPointerIntent = { [weak self] in
            self?.requestInteraction(trigger: .pointer)
        }
        panel.onCancelRequested = { [weak self] in
            self?.closeRequested(trigger: .keyboardNavigation)
        }
    }

    /// Stores authoritative geometry even while hidden. A stale revision is ignored, and
    /// only a card that logically belongs at presentation is moved by a refresh.
    func updatePlacementContext(
        _ context: CardPlacementContext,
        logicalState: CatLogicalPlacement,
        dismissalSourceRect: CGRect?
    ) -> CardPlacementUpdateOutcome {
        guard context.placementRevision >= (placementContext?.placementRevision ?? 0) else {
            return .init(animationWasRebased: false)
        }

        let previousFrame = panel.frame
        placementContext = context
        logicalPlacement = logicalState
        if let installedContent {
            regionMeasurements = estimatedMeasurements(
                notification: installedContent.notification,
                preferences: installedContent.preferences
            )
            refreshContentLayout()
        }
        _ = resolveStableFrame()

        guard panel.isVisible, logicalState == .presentation else {
            return .init(animationWasRebased: false)
        }
        if currentVisualOperation == .dismissing {
            self.dismissalSourceRect = dismissalSourceRect
        }
        if pendingAnimation != nil {
            panel.setFrame(previousFrame, display: true)
            rebaseCurrentVisualOperation(animated: true)
            return .init(animationWasRebased: true)
        }
        applyStableFrame()
        return .init(animationWasRebased: false)
    }

    /// Updates only queue metadata. It deliberately leaves presentation operation and
    /// session ownership untouched, so transient deadlines cannot be restarted here.
    func updateQueueContext(
        _ context: CardQueueContext,
        revision: NotificationQueueRevision
    ) {
        guard revision >= queueContextRevision else {
            logger.error(
                "Stale queue context revision=\(revision, privacy: .public) current=\(self.queueContextRevision, privacy: .public) ignored=true"
            )
            return
        }
        guard revision != queueContextRevision || context != queueContext else { return }
        queueContext = context
        queueContextRevision = revision
        guard installedContent != nil else { return }

        let previousFrame = panel.frame
        refreshContentLayout(resetMeasurementsForQueueFooter: true)
        _ = resolveStableFrame()
        guard panel.isVisible, logicalPlacement == .presentation else { return }
        panel.setFrame(previousFrame, display: true)
        applyResizeForCurrentVisualMode()
    }

    func cancelPresentationAnimation() {
        guard let id = currentOperationID else { return }
        finishAnimation(id: id, result: .cancelled)
        currentOperationID = nil
        currentVisualOperation = nil
        dismissalSourceRect = nil
    }

    func applyVisualPreferences(_ preferences: EffectiveAnimationPreferences) {
        let modeChanged = visualPreferences.mode != preferences.mode
        visualPreferences = preferences
        currentOperationUsesReducedMotion = preferences.mode != .full
        if modeChanged, pendingAnimation != nil {
            completeCurrentVisualOperationImmediately()
        }
    }

    /// Appearance-only refresh. It neither begins a visual operation nor changes session,
    /// queue, content revision, placement, or transient timing.
    func applyAccessibilityDisplayOptions(_ options: AccessibilityDisplayOptions) {
        guard options != accessibilityDisplayOptions else { return }
        accessibilityDisplayOptions = options
        logger.info(
            "Accessibility options changed reduceMotion=\(options.reduceMotion, privacy: .public) increaseContrast=\(options.increaseContrast, privacy: .public) reduceTransparency=\(options.reduceTransparency, privacy: .public) differentiateWithoutColor=\(options.differentiateWithoutColor, privacy: .public)"
        )
        panel.hasShadow = !options.increaseContrast
        guard installedContent != nil else { return }
        refreshHostedInteractionState()
    }

    func announceStableCard(
        sessionID: PresentationSessionID,
        contentRevision: UInt64,
        category: CardAccessibilityAnnouncementCategory
    ) {
        guard panel.isVisible,
              installedSessionID == sessionID,
              let installedContent else {
            accessibilityAnnouncer.cancelPending(reason: "stale-session")
            return
        }
        let content = makeCardContent(
            notification: installedContent.notification,
            preferences: installedContent.preferences
        )
        accessibilityAnnouncer.announceStable(
            model: .init(content: content),
            sessionID: sessionID,
            contentRevision: contentRevision,
            category: category
        )
    }

    func forceHide(exit: CardInteractionExit = .globalDisable) {
        accessibilityAnnouncer.cancelPending(reason: exit.rawValue)
        cancelPresentationAnimation()
        hostingModelRevision &+= 1
        pendingRegionMeasurement = nil
        if let sessionID = installedSessionID {
            interactionCoordinator.prepareExit(
                exit, for: sessionID, panelIsKey: panel.isKeyWindow
            )
        }
        interactionFocusGeneration = nil
        keyboardFocusTarget = nil
        panel.returnToPassiveMode()
        suppressCloseCallback = true
        panel.orderOut(nil)
        suppressCloseCallback = false
        if let sessionID = installedSessionID {
            interactionCoordinator.completeExit(for: sessionID)
            interactionCoordinator.clearPresentation(sessionID)
        }
        installedSessionID = nil
        panel.activeCardIsDismissible = false
        panel.alphaValue = 1
    }

    var isVisible: Bool { panel.isVisible }

    func present(
        notification: DockCatNotification,
        preferences: DockCatPreferences,
        from sourceRect: CGRect,
        visualPreferences: EffectiveAnimationPreferences,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        beginPassivePresentation(sessionID)
        self.visualPreferences = visualPreferences
        let reducedMotion = Self.usesReducedMotionForCardAnimations(visualPreferences)
        let id = beginOperation(
            sessionID: sessionID, operation: .presenting,
            reducedMotion: reducedMotion
        )
        install(notification: notification, preferences: preferences)
        let finalFrame = resolveStableFrame()
        let startFrame = reducedMotion
            ? finalFrame
            : handoffFrame(from: sourceRect, cardFrame: finalFrame)
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: true)
        panel.orderFrontRegardless()
        if visualPreferences.mode == .animationsPaused {
            panel.setFrame(finalFrame, display: true)
            panel.alphaValue = 1
            currentOperationID = nil
            currentVisualOperation = nil
            return .completed
        }
        return await animate(id: id, duration: reducedMotion ? 0.12 : 0.22) { [panel] in
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } cancel: { [weak self, panel] in
            panel.orderOut(nil)
            self?.applyStableFrame()
            panel.alphaValue = 1
        } completion: { [weak self, panel] in
            self?.applyStableFrame()
            panel.alphaValue = 1
        }
    }

    func present(
        notification: DockCatNotification,
        preferences: DockCatPreferences,
        from sourceRect: CGRect,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        await present(
            notification: notification,
            preferences: preferences,
            from: sourceRect,
            visualPreferences: Self.legacyPolicy(reducedMotion: reducedMotion),
            sessionID: sessionID
        )
    }

    func replace(
        notification: DockCatNotification,
        preferences: DockCatPreferences,
        visualPreferences: EffectiveAnimationPreferences,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        self.visualPreferences = visualPreferences
        let reducedMotion = Self.usesReducedMotionForCardAnimations(visualPreferences)
        guard panel.isVisible else {
            return await present(
                notification: notification, preferences: preferences,
                from: stableCardFrame ?? .zero,
                visualPreferences: visualPreferences,
                sessionID: sessionID
            )
        }
        beginPassivePresentation(sessionID)
        let id = beginOperation(
            sessionID: sessionID, operation: .replacing,
            reducedMotion: reducedMotion
        )
        if visualPreferences.mode == .animationsPaused {
            install(notification: notification, preferences: preferences)
            applyStableFrame()
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            currentOperationID = nil
            currentVisualOperation = nil
            return .completed
        }
        if reducedMotion {
            install(notification: notification, preferences: preferences)
            _ = resolveStableFrame()
            applyStableFrame()
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            // Let SwiftUI's coalesced semantic-region measurement install its valid final
            // frame without introducing a fade or spatial transition.
            await withCheckedContinuation {
                (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            applyStableFrame()
            currentOperationID = nil
            currentVisualOperation = nil
            return .completed
        }
        let fadeOut = await animate(id: id, duration: reducedMotion ? 0.10 : 0.16) { [panel] in
            panel.animator().alphaValue = 0.15
        } cancel: { [panel] in
            panel.alphaValue = 1
        } completion: {}
        guard fadeOut == .completed, currentOperationID == id else { return .cancelled }

        let previousFrame = panel.frame
        install(notification: notification, preferences: preferences)
        let finalFrame = resolveStableFrame()
        panel.setFrame(previousFrame, display: true)
        panel.alphaValue = 0.15
        return await animate(id: id, duration: reducedMotion ? 0.10 : 0.16) { [panel] in
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } cancel: { [weak self, panel] in
            self?.applyStableFrame()
            panel.alphaValue = 1
        } completion: { [weak self, panel] in
            self?.applyStableFrame()
            panel.alphaValue = 1
        }
    }

    func replace(
        notification: DockCatNotification,
        preferences: DockCatPreferences,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        await replace(
            notification: notification,
            preferences: preferences,
            visualPreferences: Self.legacyPolicy(reducedMotion: reducedMotion),
            sessionID: sessionID
        )
    }

    func dismissActive(
        toward sourceRect: CGRect?,
        visualPreferences: EffectiveAnimationPreferences,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        accessibilityAnnouncer.cancelPending(reason: "dismissal")
        self.visualPreferences = visualPreferences
        let reducedMotion = Self.usesReducedMotionForCardAnimations(visualPreferences)
        let id = beginOperation(
            sessionID: sessionID, operation: .dismissing,
            reducedMotion: reducedMotion
        )
        let currentFrame = panel.frame
        dismissalSourceRect = sourceRect
        let targetFrame = (reducedMotion || sourceRect == nil)
            ? currentFrame
            : handoffFrame(from: sourceRect!, cardFrame: currentFrame)
        if visualPreferences.mode == .animationsPaused {
            suppressCloseCallback = true
            panel.orderOut(nil)
            suppressCloseCallback = false
            finishInteractionAfterPanelHidden(sessionID: sessionID)
            applyStableFrame()
            panel.alphaValue = 1
            currentOperationID = nil
            currentVisualOperation = nil
            dismissalSourceRect = nil
            return .completed
        }
        return await animate(id: id, duration: reducedMotion ? 0.12 : 0.20) { [panel] in
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: true)
        } cancel: { [weak self, panel] in
            self?.applyStableFrame()
            panel.alphaValue = 1
        } completion: { [weak self, panel] in
            guard self?.currentOperationID == id else { return }
            self?.suppressCloseCallback = true
            panel.orderOut(nil)
            self?.suppressCloseCallback = false
            self?.finishInteractionAfterPanelHidden(sessionID: sessionID)
            self?.applyStableFrame()
            panel.alphaValue = 1
        }
    }

    func prepareForDismissal(
        exit: CardInteractionExit,
        sessionID: PresentationSessionID
    ) {
        guard installedSessionID == sessionID else { return }
        interactionCoordinator.prepareExit(
            exit, for: sessionID, panelIsKey: panel.isKeyWindow
        )
        interactionFocusGeneration = nil
        keyboardFocusTarget = nil
        panel.returnToPassiveMode()
    }

    func dismissActive(
        toward sourceRect: CGRect?,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        await dismissActive(
            toward: sourceRect,
            visualPreferences: Self.legacyPolicy(reducedMotion: reducedMotion),
            sessionID: sessionID
        )
    }

    private static func legacyPolicy(
        reducedMotion: Bool
    ) -> EffectiveAnimationPreferences {
        EffectiveAnimationPreferences(inputs: .init(
            appReducedMotion: reducedMotion,
            systemReducedMotion: false,
            disableWalking: false,
            pauseAnimations: false,
            idleAnimation: true,
            animationSpeed: 1,
            catScale: 1
        ))
    }

    /// Disable Walking is a cat-travel preference. Card surfaces only reduce their
    /// presentation, replacement, and dismissal animations for effective Reduced Motion.
    static func usesReducedMotionForCardAnimations(
        _ preferences: EffectiveAnimationPreferences
    ) -> Bool {
        preferences.mode == .reducedMotion
    }

    private func install(
        notification: DockCatNotification,
        preferences: DockCatPreferences
    ) {
        installedContent = InstalledContent(
            notification: notification,
            preferences: preferences
        )
        panel.activeCardIsDismissible = preferences.transientManuallyDismissible
            || notification.presentation == .persistent
        regionMeasurements = estimatedMeasurements(
            notification: notification,
            preferences: preferences
        )
        recalculateLayoutPlan()
        hostingModelRevision &+= 1
        let view = makeCardView(notification: notification, preferences: preferences)
        if let hostingView {
            hostingView.rootView = view
            hostingView.frame = CGRect(origin: .zero, size: measuredCardSize)
            hostingView.layoutSubtreeIfNeeded()
        } else {
            let hosting = CardHostingView(rootView: view)
            hosting.frame = CGRect(origin: .zero, size: measuredCardSize)
            panel.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            hostingView = hosting
        }
    }

    private func makeCardView(
        notification: DockCatNotification,
        preferences: DockCatPreferences
    ) -> NotificationCardView {
        let actionSessionID = installedSessionID
        let content = makeCardContent(
            notification: notification,
            preferences: preferences
        )
        let accessibility = NotificationCardAccessibilityModel(content: content)
        let appearanceCategory: CardAppearanceCategory = panel.effectiveAppearance.bestMatch(
            from: [.aqua, .darkAqua]
        ) == .darkAqua ? .dark : .light
        let appearance = CardAccessibilityAppearancePolicy.resolve(
            options: accessibilityDisplayOptions,
            appearance: appearanceCategory,
            interactionMode: interactionCoordinator.state.mode,
            presentation: content.presentation
        )
        logger.info(
            "Card accessibility semantics=\(accessibility.orderedElements.count, privacy: .public) appearance=\(appearance.category, privacy: .public)"
        )
        let modelRevision = hostingModelRevision
        return NotificationCardView(
            content: content,
            accessibility: accessibility,
            accessibilityAppearance: appearance,
            isInteractive: panel.isInteractive,
            actionURL: notification.actionURL,
            cardWidth: measuredCardSize.width,
            layoutPlan: layoutPlan,
            interactionFocusGeneration: interactionFocusGeneration,
            preferredFocusTarget: keyboardFocusTarget,
            measurementsChanged: { [weak self] measurements in
                self?.receiveRegionMeasurements(
                    measurements,
                    notificationID: notification.id,
                    hostingModelRevision: modelRevision
                )
            },
            focusChanged: { [weak self] target in
                self?.keyboardFocusTarget = target
            },
            requestInteraction: { [weak self] trigger in
                guard let actionSessionID else { return }
                self?.requestInteraction(
                    trigger: trigger,
                    expectedSessionID: actionSessionID,
                    expectedHostingModelRevision: modelRevision
                )
            },
            closeRequested: { [weak self] in
                guard let actionSessionID else { return }
                self?.closeRequested(
                    trigger: .pointer,
                    expectedSessionID: actionSessionID,
                    expectedHostingModelRevision: modelRevision
                )
            },
            openRequested: { [weak self] url in
                guard let actionSessionID else { return }
                self?.openRequested(
                    url,
                    trigger: .pointer,
                    expectedSessionID: actionSessionID,
                    expectedHostingModelRevision: modelRevision
                )
            }
        )
    }

    private func makeCardContent(
        notification: DockCatNotification,
        preferences: DockCatPreferences
    ) -> NotificationCardContent {
        let presentation: CardPresentationKind
        switch notification.presentation {
        case .transient: presentation = .transient
        case .persistent: presentation = .persistent
        }
        return NotificationCardContent(
            notificationID: notification.id,
            sourceName: notification.sourceName,
            title: notification.title,
            message: notification.message,
            presentation: presentation,
            hasOpenAction: preferences.clickCardOpensAction
                && notification.actionURL != nil,
            canDismiss: preferences.transientManuallyDismissible
                || notification.presentation == .persistent,
            queueContext: queueContext
        )
    }

    /// A new queued card starts passive. An in-place external content revision keeps the
    /// current interaction token so an equivalent control can retain logical focus.
    private func beginPassivePresentation(_ sessionID: PresentationSessionID) {
        accessibilityAnnouncer.cancelPending(reason: "replacement")
        if installedSessionID == sessionID { return }
        if let oldSessionID = installedSessionID {
            interactionCoordinator.prepareExit(
                .replacement, for: oldSessionID, panelIsKey: panel.isKeyWindow
            )
            interactionFocusGeneration = nil
            keyboardFocusTarget = nil
            panel.returnToPassiveMode()
            interactionCoordinator.completeExit(for: oldSessionID)
            interactionCoordinator.clearPresentation(oldSessionID)
        } else {
            panel.returnToPassiveMode()
        }
        installedSessionID = sessionID
        interactionCoordinator.beginPresentation(sessionID)
    }

    private func requestInteraction(
        trigger: CardInteractionTrigger,
        expectedSessionID: PresentationSessionID? = nil,
        expectedHostingModelRevision: UInt64? = nil
    ) {
        guard panel.isVisible, let sessionID = installedSessionID,
              expectedSessionID == nil || expectedSessionID == sessionID,
              expectedHostingModelRevision == nil
                || expectedHostingModelRevision == hostingModelRevision,
              validateInteractionSession?(sessionID) != false else { return }
        logger.info(
            "Accessibility interaction requested=\(trigger == .accessibility, privacy: .public) generation=\(sessionID.generation, privacy: .public)"
        )
        _ = interactionCoordinator.requestInteraction(
            for: sessionID,
            trigger: trigger,
            setPanelInteractive: { [weak self] in
                self?.panel.enterInteractiveMode()
            },
            makePanelKey: { [weak self] generation in
                self?.makePanelKey(focusGeneration: generation)
            }
        )
    }

    private func closeRequested(
        trigger: CardInteractionTrigger,
        expectedSessionID: PresentationSessionID? = nil,
        expectedHostingModelRevision: UInt64? = nil
    ) {
        guard panel.isVisible, panel.activeCardIsDismissible,
              let sessionID = installedSessionID,
              expectedSessionID == nil || expectedSessionID == sessionID,
              expectedHostingModelRevision == nil
                || expectedHostingModelRevision == hostingModelRevision,
              validateInteractionSession?(sessionID) != false else { return }
        interactionCoordinator.closeRequested(
            for: sessionID,
            trigger: trigger,
            setPanelInteractive: { [weak self] in
                self?.panel.enterInteractiveMode()
            },
            makePanelKey: { [weak self] generation in
                self?.makePanelKey(focusGeneration: generation)
            }
        )
    }

    private func openRequested(
        _ url: URL,
        trigger: CardInteractionTrigger,
        expectedSessionID: PresentationSessionID? = nil,
        expectedHostingModelRevision: UInt64? = nil
    ) {
        guard panel.isVisible, let sessionID = installedSessionID,
              expectedSessionID == nil || expectedSessionID == sessionID,
              expectedHostingModelRevision == nil
                || expectedHostingModelRevision == hostingModelRevision,
              validateInteractionSession?(sessionID) != false else { return }
        _ = interactionCoordinator.openRequested(
            url,
            for: sessionID,
            trigger: trigger,
            setPanelInteractive: { [weak self] in
                self?.panel.enterInteractiveMode()
            },
            makePanelKey: { [weak self] generation in
                self?.makePanelKey(focusGeneration: generation)
            }
        )
    }

    private func makePanelKey(focusGeneration: UInt64) {
        panel.makeKeyAndOrderFront(nil)
        if let hostingView { panel.makeFirstResponder(hostingView) }
        interactionFocusGeneration = focusGeneration
        if let installedContent {
            let content = makeCardContent(
                notification: installedContent.notification,
                preferences: installedContent.preferences
            )
            let target = CardInitialFocusTarget.resolve(
                hasOpenAction: content.hasOpenAction,
                canDismiss: content.canDismiss,
                bodySupportsKeyboardScrolling: layoutPlan.bodyScrolls
            )
            logger.info(
                "Keyboard focus destination=\(target?.rawValue ?? "none", privacy: .public)"
            )
            keyboardFocusTarget = target.map(CardKeyboardTarget.init)
        }
        // Do not replace SwiftUI's root while NSPanel is still dispatching the first mouse
        // event. Deferring focus installation keeps the original control's mouse-up/action
        // path intact; background clicks install deterministic keyboard focus next turn.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.interactionFocusGeneration == focusGeneration,
                  self.panel.isInteractive else { return }
            self.refreshHostedInteractionState()
        }
    }

    private func refreshHostedInteractionState() {
        guard let installedContent, let hostingView else { return }
        hostingModelRevision &+= 1
        hostingView.rootView = makeCardView(
            notification: installedContent.notification,
            preferences: installedContent.preferences
        )
        hostingView.layoutSubtreeIfNeeded()
    }

    private func finishInteractionAfterPanelHidden(
        sessionID: PresentationSessionID
    ) {
        interactionCoordinator.completeExit(for: sessionID)
        interactionCoordinator.clearPresentation(sessionID)
        if installedSessionID == sessionID { installedSessionID = nil }
        interactionFocusGeneration = nil
        keyboardFocusTarget = nil
        panel.returnToPassiveMode()
        panel.activeCardIsDismissible = false
    }

    private func estimatedMeasurements(
        notification: DockCatNotification,
        preferences: DockCatPreferences
    ) -> CardContentRegionMeasurements {
        let metrics = CardContentLayoutMetrics.standard
        let textWidth = max(
            0,
            min(Double(availableCardSize().width), metrics.preferredWidth)
                - metrics.horizontalPadding * 2
        )
        let captionFont = NSFont.preferredFont(forTextStyle: .caption1)
        let headlineFont = NSFont.preferredFont(forTextStyle: .headline)
        let bodyFont = NSFont.preferredFont(forTextStyle: .body)
        let footerFont = NSFont.preferredFont(forTextStyle: .caption2)
        let titleHeight = naturalTextHeight(
            notification.title,
            font: headlineFont,
            width: textWidth,
            maximumLines: metrics.maximumTitleLines
        )
        return .init(
            headerHeight: ceil(max(16, captionFont.boundingRectForFont.height)),
            titleHeight: titleHeight,
            bodyHeight: naturalTextHeight(
                notification.message, font: bodyFont, width: textWidth
            ),
            actionsHeight: preferences.clickCardOpensAction
                && notification.actionURL != nil ? 22 : 0,
            queueFooterHeight: queueContext.isVisible
                ? ceil(footerFont.boundingRectForFont.height) : 0
        )
    }

    private func naturalTextHeight(
        _ text: String,
        font: NSFont,
        width: Double,
        maximumLines: Int? = nil
    ) -> Double {
        guard !text.isEmpty, width > 0 else { return 0 }
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let natural = ceil(bounds.height)
        guard let maximumLines else { return natural }
        return min(
            natural,
            ceil(font.boundingRectForFont.height) * Double(maximumLines)
        )
    }

    private func refreshContentLayout(resetMeasurementsForQueueFooter: Bool = false) {
        guard let installedContent else { return }
        if resetMeasurementsForQueueFooter {
            regionMeasurements = .init(
                headerHeight: regionMeasurements.headerHeight,
                titleHeight: regionMeasurements.titleHeight,
                bodyHeight: regionMeasurements.bodyHeight,
                actionsHeight: regionMeasurements.actionsHeight,
                queueFooterHeight: queueContext.isVisible
                    ? ceil(NSFont.preferredFont(
                        forTextStyle: .caption2
                    ).boundingRectForFont.height)
                    : 0
            )
        }
        recalculateLayoutPlan()
        hostingModelRevision &+= 1
        hostingView?.rootView = makeCardView(
            notification: installedContent.notification,
            preferences: installedContent.preferences
        )
        hostingView?.frame = CGRect(origin: .zero, size: measuredCardSize)
        hostingView?.layoutSubtreeIfNeeded()
    }

    private func recalculateLayoutPlan() {
        let availableSize = availableCardSize()
        layoutPlan = CardContentLayoutPlanner.plan(.init(
            availableWidth: availableSize.width,
            availableHeight: availableSize.height,
            measurements: regionMeasurements
        ))
        measuredCardSize = CGSize(layoutPlan.cardSize)
        panel.setContentSize(measuredCardSize)
        hostingView?.frame = CGRect(origin: .zero, size: measuredCardSize)
    }

    /// Screen margin is removed here to provide the planner's placement-safe dimensions.
    /// CardPlacementPlanner uses the same margin to position that already-bounded size;
    /// it does not subtract the margin from the card a second time.
    private func availableCardSize() -> CGSize {
        guard let placementContext else {
            return CGSize(
                width: CardLayoutMetrics.preferredWidth,
                height: CardLayoutMetrics.maximumHeight
            )
        }
        return CGSize(
            width: max(
                0,
                placementContext.visibleScreenFrame.width
                    - CardLayoutMetrics.screenMargin * 2
            ),
            height: max(
                0,
                placementContext.visibleScreenFrame.height
                    - CardLayoutMetrics.screenMargin * 2
            )
        )
    }

    private func receiveRegionMeasurements(
        _ measurements: CardContentRegionMeasurements,
        notificationID: UUID,
        hostingModelRevision: UInt64
    ) {
        guard installedContent?.notification.id == notificationID,
              hostingModelRevision == self.hostingModelRevision else { return }
        pendingRegionMeasurement = .init(
            measurements: measurements,
            notificationID: notificationID,
            hostingModelRevision: hostingModelRevision
        )
        guard !measurementCallbackScheduled else { return }
        measurementCallbackScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.measurementCallbackScheduled = false
            guard let newest = self.pendingRegionMeasurement else { return }
            self.pendingRegionMeasurement = nil
            self.applyRegionMeasurements(newest)
        }
    }

    private func applyRegionMeasurements(
        _ pending: PendingRegionMeasurement
    ) {
        guard installedContent?.notification.id == pending.notificationID,
              pending.hostingModelRevision == hostingModelRevision,
              measurementsDiffer(
                pending.measurements, regionMeasurements
              ) else { return }
        let previousFrame = panel.frame
        regionMeasurements = pending.measurements
        refreshContentLayout()
        _ = resolveStableFrame()
        guard panel.isVisible, logicalPlacement == .presentation else { return }
        panel.setFrame(previousFrame, display: true)
        applyResizeForCurrentVisualMode()
    }

    private func measurementsDiffer(
        _ lhs: CardContentRegionMeasurements,
        _ rhs: CardContentRegionMeasurements
    ) -> Bool {
        abs(lhs.headerHeight - rhs.headerHeight) > Self.measurementEpsilon
            || abs(lhs.titleHeight - rhs.titleHeight) > Self.measurementEpsilon
            || abs(lhs.bodyHeight - rhs.bodyHeight) > Self.measurementEpsilon
            || abs(lhs.actionsHeight - rhs.actionsHeight) > Self.measurementEpsilon
            || abs(lhs.queueFooterHeight - rhs.queueFooterHeight) > Self.measurementEpsilon
    }

    private func applyResizeForCurrentVisualMode() {
        let sizeAnimationApplied = pendingAnimation != nil
            && visualPreferences.mode == .full
        if pendingAnimation != nil {
            rebaseCurrentVisualOperation(animated: sizeAnimationApplied)
        } else {
            applyStableFrame()
        }
        if let notificationID = installedContent?.notification.id {
            logger.info(
                "Card layout notification=\(notificationID, privacy: .public) pending=\(self.queueContext.pendingCount, privacy: .public) width=\(self.measuredCardSize.width, privacy: .public) height=\(self.measuredCardSize.height, privacy: .public) bodyScrolls=\(self.layoutPlan.bodyScrolls, privacy: .public) degradation=\(self.layoutPlan.degradation.rawValue, privacy: .public) placementRevision=\(self.placementContext?.placementRevision ?? 0, privacy: .public) queueRevision=\(self.queueContextRevision, privacy: .public) sizeAnimated=\(sizeAnimationApplied, privacy: .public)"
            )
        }
    }

    @discardableResult
    private func resolveStableFrame() -> CGRect {
        guard let context = placementContext else {
            let frame = CGRect(origin: panel.frame.origin, size: measuredCardSize)
            stableCardFrame = frame
            return frame
        }
        let plan = CardPlacementPlanner.plan(
            CardPlacementInput(
                presentationAnchor: Point(context.presentationAnchor),
                dockEdge: context.dockEdge,
                cardSize: Size(measuredCardSize),
                visibleScreenFrame: Rect(context.visibleScreenFrame),
                catExclusionFrame: context.catExclusionFrame.map(Rect.init),
                offset: context.offset,
                screenMargin: Double(CardLayoutMetrics.screenMargin)
            )
        )
        let frame = CGRect(plan.frame)
        stableCardFrame = frame
        logger.info(
            "Card placement edge=\(context.dockEdge.rawValue, privacy: .public) width=\(frame.width, privacy: .public) height=\(frame.height, privacy: .public) clamped=\(plan.wasClamped, privacy: .public) collisionFallback=\(plan.usedCollisionFallback, privacy: .public) revision=\(context.placementRevision, privacy: .public) degraded=\(plan.degradation.rawValue, privacy: .public)"
        )
        return frame
    }

    private func applyStableFrame() {
        panel.setFrame(stableCardFrame ?? resolveStableFrame(), display: true)
    }

    private func beginOperation(
        sessionID: PresentationSessionID,
        operation: VisualOperation,
        reducedMotion: Bool
    ) -> OperationID {
        cancelPresentationAnimation()
        operationSequence &+= 1
        let id = OperationID(sessionID: sessionID, sequence: operationSequence)
        currentOperationID = id
        currentVisualOperation = operation
        currentOperationUsesReducedMotion = reducedMotion
        if operation != .dismissing { dismissalSourceRect = nil }
        return id
    }

    private func animate(
        id: OperationID,
        duration: TimeInterval,
        animations: @escaping @MainActor () -> Void,
        cancel: @escaping @MainActor () -> Void,
        completion: @escaping @MainActor () -> Void
    ) async -> PresentationAnimationResult {
        await withTaskCancellationHandler {
            guard !Task.isCancelled, currentOperationID == id else { return .cancelled }
            return await withCheckedContinuation { continuation in
                let animationPlacementRevision = placementContext?.placementRevision ?? 0
                pendingAnimation = PendingAnimation(
                    id: id,
                    placementRevision: animationPlacementRevision,
                    continuation: continuation,
                    cancel: cancel
                )
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.allowsImplicitAnimation = true
                    animations()
                } completionHandler: { [weak self] in
                    Task { @MainActor in
                        guard self?.currentOperationID == id else { return }
                        if self?.pendingAnimation?.placementRevision
                            != self?.placementContext?.placementRevision {
                            self?.rebaseCurrentVisualOperation(animated: false)
                        }
                        completion()
                        self?.finishAnimation(id: id, result: .completed)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishAnimation(id: id, result: .cancelled)
            }
        }
    }

    private func finishAnimation(id: OperationID, result: PresentationAnimationResult) {
        guard let pending = pendingAnimation, pending.id == id else { return }
        pendingAnimation = nil
        if result == .cancelled { pending.cancel() }
        pending.continuation.resume(returning: result)
    }

    private func completeCurrentVisualOperationImmediately() {
        guard let pending = pendingAnimation,
              pending.id == currentOperationID,
              let operation = currentVisualOperation else { return }
        pendingAnimation = nil
        panel.contentView?.layer?.removeAllAnimations()
        switch operation {
        case .presenting, .replacing:
            applyStableFrame()
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        case .dismissing:
            suppressCloseCallback = true
            panel.orderOut(nil)
            suppressCloseCallback = false
            finishInteractionAfterPanelHidden(sessionID: pending.id.sessionID)
            applyStableFrame()
            panel.alphaValue = 1
        }
        currentOperationID = nil
        currentVisualOperation = nil
        dismissalSourceRect = nil
        pending.continuation.resume(returning: .completed)
    }

    private func rebaseCurrentVisualOperation(animated: Bool) {
        guard let operation = currentVisualOperation else {
            applyStableFrame()
            return
        }
        let stableFrame = stableCardFrame ?? resolveStableFrame()
        let targetFrame: CGRect
        switch operation {
        case .presenting, .replacing:
            targetFrame = stableFrame
        case .dismissing:
            if currentOperationUsesReducedMotion || dismissalSourceRect == nil {
                targetFrame = stableFrame
            } else {
                targetFrame = handoffFrame(
                    from: dismissalSourceRect!, cardFrame: stableFrame
                )
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.08
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func handoffFrame(from sourceRect: CGRect, cardFrame: CGRect) -> CGRect {
        CGRect(
            x: sourceRect.midX - cardFrame.width * 0.18,
            y: sourceRect.midY - cardFrame.height * 0.18,
            width: cardFrame.width * 0.36,
            height: cardFrame.height * 0.36
        )
    }

    var panelFrameForTesting: CGRect { panel.frame }
    var panelIsVisibleForTesting: Bool { panel.isVisible }
    var measuredCardSizeForTesting: CGSize { measuredCardSize }
    var stableCardFrameForTesting: CGRect? { stableCardFrame }
    var placementRevisionForTesting: UInt64? { placementContext?.placementRevision }
    var queueContextForTesting: CardQueueContext { queueContext }
    var queueContextRevisionForTesting: NotificationQueueRevision {
        queueContextRevision
    }
    var installedNotificationIDForTesting: UUID? {
        installedContent?.notification.id
    }
    var operationSequenceForTesting: UInt64 { operationSequence }
    var layoutPlanForTesting: CardContentLayoutPlan { layoutPlan }
    var interactionModeForTesting: CardInteractionMode {
        interactionCoordinator.state.mode
    }
    var panelCanBecomeKeyForTesting: Bool { panel.canBecomeKey }
    var panelIsKeyForTesting: Bool { panel.isKeyWindow }
    var panelIsInteractiveForTesting: Bool { panel.isInteractive }
    var accessibilityModelForTesting: NotificationCardAccessibilityModel? {
        guard let installedContent else { return nil }
        return .init(content: makeCardContent(
            notification: installedContent.notification,
            preferences: installedContent.preferences
        ))
    }
    var accessibilityAppearanceForTesting: CardAccessibilityAppearance? {
        guard let installedContent else { return nil }
        let content = makeCardContent(
            notification: installedContent.notification,
            preferences: installedContent.preferences
        )
        return CardAccessibilityAppearancePolicy.resolve(
            options: accessibilityDisplayOptions,
            appearance: .light,
            interactionMode: interactionCoordinator.state.mode,
            presentation: content.presentation
        )
    }
    var hostingViewIdentityForTesting: ObjectIdentifier? {
        hostingView.map(ObjectIdentifier.init)
    }
    func requestAccessibilityInteractionForTesting() {
        requestInteraction(trigger: .accessibility)
    }

    func windowWillClose(_ notification: Notification) {
        if !suppressCloseCallback { onDismiss?() }
    }
}

private extension Point {
    init(_ point: CGPoint) { self.init(x: point.x, y: point.y) }
}

private extension Size {
    init(_ size: CGSize) { self.init(width: size.width, height: size.height) }
}

private extension CGSize {
    init(_ size: Size) { self.init(width: size.width, height: size.height) }
}

private extension Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

private extension CGRect {
    init(_ rect: Rect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}
