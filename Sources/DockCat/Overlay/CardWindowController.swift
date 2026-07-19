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
    static let preferredWidth: CGFloat = 340
    static let minimumWidth: CGFloat = 220
    static let minimumHeight: CGFloat = 120
    static let maximumHeight: CGFloat = 480
    static let screenMargin: CGFloat = 10
}

@MainActor
private final class CardHostingView: NSHostingView<NotificationCardView> {
    var fittingSizeDidChange: (() -> Void)?
    private var callbackIsScheduled = false

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        guard fittingSizeDidChange != nil, !callbackIsScheduled else { return }
        callbackIsScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.callbackIsScheduled = false
            self.fittingSizeDidChange?()
        }
    }
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

    private let panel = CardOverlayPanel()
    private let logger = Logger(subsystem: "com.example.DockCat", category: "CardPlacement")
    private var placementContext: CardPlacementContext?
    private var logicalPlacement: CatLogicalPlacement = .home
    private var measuredCardSize = CGSize(
        width: CardLayoutMetrics.preferredWidth,
        height: CardLayoutMetrics.minimumHeight
    )
    private var stableCardFrame: CGRect?
    private var installedContent: InstalledContent?
    private weak var hostingView: CardHostingView?
    private var operationSequence: UInt64 = 0
    private var currentOperationID: OperationID?
    private var currentVisualOperation: VisualOperation?
    private var currentOperationUsesReducedMotion = false
    private var visualPreferences: EffectiveAnimationPreferences = .default
    private var dismissalSourceRect: CGRect?
    private var pendingAnimation: PendingAnimation?
    private var suppressCloseCallback = false
    var onDismiss: (() -> Void)?

    override init() {
        super.init()
        panel.delegate = self
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
            install(
                notification: installedContent.notification,
                preferences: installedContent.preferences
            )
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

    func forceHide() {
        cancelPresentationAnimation()
        suppressCloseCallback = true
        panel.orderOut(nil)
        suppressCloseCallback = false
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
            self?.applyStableFrame()
            panel.alphaValue = 1
        }
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
        let width = desiredCardWidth()
        let view = NotificationCardView(
            notification: notification,
            canDismiss: preferences.transientManuallyDismissible
                || notification.presentation == .persistent,
            opensAction: preferences.clickCardOpensAction,
            cardWidth: width
        ) { [weak self] in
            self?.onDismiss?()
        }
        let hosting = CardHostingView(rootView: view)
        hosting.frame = CGRect(
            x: 0, y: 0, width: width, height: CardLayoutMetrics.maximumHeight
        )
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        hostingView = hosting
        applyMeasuredContentSize(from: hosting)
        hosting.fittingSizeDidChange = { [weak self, weak hosting] in
            guard let self, let hosting else { return }
            self.handleFittingSizeChange(from: hosting)
        }
    }

    private func desiredCardWidth() -> CGFloat {
        guard let placementContext else { return CardLayoutMetrics.preferredWidth }
        let available = max(
            0,
            placementContext.visibleScreenFrame.width - CardLayoutMetrics.screenMargin * 2
        )
        if available < CardLayoutMetrics.minimumWidth { return available }
        return min(CardLayoutMetrics.preferredWidth, available)
    }

    private func applyMeasuredContentSize(from hosting: CardHostingView) {
        let fitting = hosting.fittingSize
        measuredCardSize = CGSize(
            width: desiredCardWidth(),
            height: min(
                CardLayoutMetrics.maximumHeight,
                max(CardLayoutMetrics.minimumHeight, fitting.height)
            )
        )
        panel.setContentSize(measuredCardSize)
        hosting.frame = CGRect(origin: .zero, size: measuredCardSize)
    }

    private func handleFittingSizeChange(from hosting: CardHostingView) {
        guard hosting === hostingView else { return }
        let previousFrame = panel.frame
        let previousSize = measuredCardSize
        applyMeasuredContentSize(from: hosting)
        guard abs(previousSize.width - measuredCardSize.width) > 0.5
                || abs(previousSize.height - measuredCardSize.height) > 0.5 else { return }
        _ = resolveStableFrame()
        guard panel.isVisible, logicalPlacement == .presentation else { return }
        panel.setFrame(previousFrame, display: true)
        if pendingAnimation != nil {
            rebaseCurrentVisualOperation(animated: true)
        } else {
            applyStableFrame()
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
