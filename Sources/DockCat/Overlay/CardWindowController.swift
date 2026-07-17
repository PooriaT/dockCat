import AppKit
import DockCatCore
import SwiftUI

struct CardPlacementUpdateOutcome {
    let animationWasRebased: Bool
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

    private let panel = CardOverlayPanel()
    private var anchor = CGPoint.zero
    private var stableCardSize = CGSize.zero
    private var placementRevision: UInt64 = 0
    private var operationSequence: UInt64 = 0
    private var currentOperationID: OperationID?
    private var currentVisualOperation: VisualOperation?
    private var currentOperationUsesReducedMotion = false
    private var dismissalSourceRect: CGRect?
    private var pendingAnimation: PendingAnimation?
    private var suppressCloseCallback = false
    var onDismiss: (() -> Void)?
    override init() { super.init(); panel.delegate = self }

    /// Stores the new presentation anchor even while hidden. Visible placement is changed
    /// only when choreography says the card belongs at presentation.
    func updatePlacement(
        above point: CGPoint,
        offset: Double,
        logicalState: CatLogicalPlacement,
        dismissalSourceRect: CGRect?
    ) -> CardPlacementUpdateOutcome {
        anchor = CGPoint(x: point.x - 170, y: point.y + offset + 55)
        placementRevision &+= 1
        guard panel.isVisible, logicalState == .presentation else {
            return .init(animationWasRebased: false)
        }

        if currentVisualOperation == .dismissing {
            self.dismissalSourceRect = dismissalSourceRect
        }
        if pendingAnimation != nil {
            rebaseCurrentVisualOperation(animated: true)
            return .init(animationWasRebased: true)
        }
        panel.setFrameOrigin(anchor)
        return .init(animationWasRebased: false)
    }

    func cancelPresentationAnimation() {
        guard let id = currentOperationID else { return }
        finishAnimation(id: id, result: .cancelled)
        currentOperationID = nil
        currentVisualOperation = nil
        dismissalSourceRect = nil
    }

    func forceHide() {
        cancelPresentationAnimation()
        suppressCloseCallback = true
        panel.orderOut(nil)
        suppressCloseCallback = false
        panel.alphaValue = 1
    }

    func present(
        notification: DockCatNotification,
        preferences: DockCatPreferences,
        from sourceRect: CGRect,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        let id = beginOperation(
            sessionID: sessionID, operation: .presenting,
            reducedMotion: reducedMotion
        )
        install(notification: notification, preferences: preferences)
        let finalFrame = CGRect(origin: anchor, size: panel.frame.size)
        stableCardSize = finalFrame.size
        let startFrame = reducedMotion ? finalFrame : CGRect(x: sourceRect.midX - finalFrame.width * 0.18, y: sourceRect.midY - finalFrame.height * 0.18, width: finalFrame.width * 0.36, height: finalFrame.height * 0.36)
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: true)
        panel.orderFrontRegardless()
        return await animate(id: id, duration: reducedMotion ? 0.12 : 0.22) { [panel] in
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } cancel: { [weak self, panel] in
            panel.orderOut(nil)
            if let self {
                panel.setFrame(CGRect(origin: self.anchor, size: self.stableCardSize), display: true)
            }
            panel.alphaValue = 1
        } completion: { [weak self, panel] in
            if let self {
                panel.setFrame(CGRect(origin: self.anchor, size: self.stableCardSize), display: true)
            }
            panel.alphaValue = 1
        }
    }

    func replace(
        notification: DockCatNotification,
        preferences: DockCatPreferences,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        guard panel.isVisible else {
            return await present(
                notification: notification, preferences: preferences,
                from: CGRect(origin: anchor, size: .zero), reducedMotion: reducedMotion,
                sessionID: sessionID
            )
        }
        let id = beginOperation(
            sessionID: sessionID, operation: .replacing,
            reducedMotion: reducedMotion
        )
        let fadeOut = await animate(id: id, duration: reducedMotion ? 0.10 : 0.16) { [panel] in
            panel.animator().alphaValue = 0.15
        } cancel: { [panel] in
            panel.alphaValue = 1
        } completion: { [weak self] in
            guard self?.currentOperationID == id else { return }
            self?.install(notification: notification, preferences: preferences)
        }
        guard fadeOut == .completed, currentOperationID == id else { return .cancelled }
        panel.alphaValue = 0.15
        return await animate(id: id, duration: reducedMotion ? 0.10 : 0.16) { [panel] in
            panel.animator().alphaValue = 1
        } cancel: { [panel] in
            panel.alphaValue = 1
        } completion: { [panel] in
            panel.alphaValue = 1
        }
    }

    func dismissActive(
        toward sourceRect: CGRect?,
        reducedMotion: Bool,
        sessionID: PresentationSessionID
    ) async -> PresentationAnimationResult {
        let id = beginOperation(
            sessionID: sessionID, operation: .dismissing,
            reducedMotion: reducedMotion
        )
        let finalFrame = panel.frame
        stableCardSize = finalFrame.size
        dismissalSourceRect = sourceRect
        let targetFrame: CGRect = (reducedMotion || sourceRect == nil) ? finalFrame : CGRect(x: sourceRect!.midX - finalFrame.width * 0.18, y: sourceRect!.midY - finalFrame.height * 0.18, width: finalFrame.width * 0.36, height: finalFrame.height * 0.36)
        let result = await animate(id: id, duration: reducedMotion ? 0.12 : 0.20) { [panel] in
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: true)
        } cancel: { [weak self, panel] in
            if let self {
                panel.setFrame(CGRect(origin: self.anchor, size: self.stableCardSize), display: true)
            }
            panel.alphaValue = 1
        } completion: { [weak self, panel] in
            if self?.currentOperationID == id {
                self?.suppressCloseCallback = true
                panel.orderOut(nil)
                self?.suppressCloseCallback = false
                if let self {
                    panel.setFrame(CGRect(origin: self.anchor, size: self.stableCardSize), display: true)
                }
                panel.alphaValue = 1
            }
        }
        return result
    }

    private func install(notification: DockCatNotification, preferences: DockCatPreferences) {
        let view = NotificationCardView(notification: notification, canDismiss: preferences.transientManuallyDismissible || notification.presentation == .persistent, opensAction: preferences.clickCardOpensAction) { [weak self] in self?.onDismiss?() }
        panel.contentView = NSHostingView(rootView: view)
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
                let animationPlacementRevision = placementRevision
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
                        if self?.pendingAnimation?.placementRevision != self?.placementRevision {
                            // The old AppKit transaction may have reached its stale frame.
                            // Reassert the latest semantic target before accepting completion.
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

    private func rebaseCurrentVisualOperation(animated: Bool) {
        guard let operation = currentVisualOperation else {
            panel.setFrameOrigin(anchor)
            return
        }
        let targetFrame: CGRect
        switch operation {
        case .presenting, .replacing:
            targetFrame = CGRect(origin: anchor, size: stableCardSize)
        case .dismissing:
            let stableFrame = CGRect(origin: anchor, size: stableCardSize)
            if currentOperationUsesReducedMotion || dismissalSourceRect == nil {
                targetFrame = stableFrame
            } else {
                let sourceRect = dismissalSourceRect!
                targetFrame = CGRect(
                    x: sourceRect.midX - stableFrame.width * 0.18,
                    y: sourceRect.midY - stableFrame.height * 0.18,
                    width: stableFrame.width * 0.36,
                    height: stableFrame.height * 0.36
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

    func windowWillClose(_ notification: Notification) { if !suppressCloseCallback { onDismiss?() } }
}
