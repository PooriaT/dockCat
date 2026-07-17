import AppKit
import DockCatCore
import SwiftUI

@MainActor
final class CardWindowController: NSObject, NSWindowDelegate {
    private let panel = CardOverlayPanel()
    private var anchor = CGPoint.zero
    private var operationID = UUID()
    private var suppressCloseCallback = false
    var onDismiss: (() -> Void)?
    override init() { super.init(); panel.delegate = self }

    func position(above point: CGPoint, offset: Double) {
        anchor = CGPoint(x: point.x - 170, y: point.y + offset + 55)
        if panel.isVisible { panel.setFrameOrigin(anchor) }
    }

    func cancelPresentationAnimation() { operationID = UUID(); panel.animator().alphaValue = panel.alphaValue }

    func forceHide() {
        cancelPresentationAnimation()
        suppressCloseCallback = true
        panel.orderOut(nil)
        suppressCloseCallback = false
        panel.alphaValue = 1
    }

    func present(notification: DockCatNotification, preferences: DockCatPreferences, from sourceRect: CGRect, reducedMotion: Bool) async -> PresentationAnimationResult {
        let id = UUID(); operationID = id
        install(notification: notification, preferences: preferences)
        let finalFrame = CGRect(origin: anchor, size: panel.frame.size)
        let startFrame = reducedMotion ? finalFrame : CGRect(x: sourceRect.midX - finalFrame.width * 0.18, y: sourceRect.midY - finalFrame.height * 0.18, width: finalFrame.width * 0.36, height: finalFrame.height * 0.36)
        panel.alphaValue = 0
        panel.setFrame(startFrame, display: true)
        panel.orderFrontRegardless()
        return await animate(id: id, duration: reducedMotion ? 0.12 : 0.22) { [panel] in
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        } completion: { [panel] completed in
            panel.setFrame(finalFrame, display: true)
            panel.alphaValue = completed ? 1 : panel.alphaValue
        }
    }

    func replace(notification: DockCatNotification, preferences: DockCatPreferences, reducedMotion: Bool) async -> PresentationAnimationResult {
        let id = UUID(); operationID = id
        guard panel.isVisible else { return await present(notification: notification, preferences: preferences, from: CGRect(origin: anchor, size: .zero), reducedMotion: reducedMotion) }
        let fadeOut = await animate(id: id, duration: reducedMotion ? 0.10 : 0.16) { [panel] in
            panel.animator().alphaValue = 0.15
        } completion: { [weak self] completed in
            guard completed, self?.operationID == id else { return }
            self?.install(notification: notification, preferences: preferences)
        }
        guard fadeOut == .completed, operationID == id else { return .cancelled }
        panel.alphaValue = 0.15
        return await animate(id: id, duration: reducedMotion ? 0.10 : 0.16) { [panel] in
            panel.animator().alphaValue = 1
        } completion: { [panel] completed in
            if completed { panel.alphaValue = 1 }
        }
    }

    func dismissActive(toward sourceRect: CGRect?, reducedMotion: Bool) async -> PresentationAnimationResult {
        let id = UUID(); operationID = id
        let finalFrame = panel.frame
        let targetFrame: CGRect = (reducedMotion || sourceRect == nil) ? finalFrame : CGRect(x: sourceRect!.midX - finalFrame.width * 0.18, y: sourceRect!.midY - finalFrame.height * 0.18, width: finalFrame.width * 0.36, height: finalFrame.height * 0.36)
        let result = await animate(id: id, duration: reducedMotion ? 0.12 : 0.20) { [panel] in
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: true)
        } completion: { [weak self, panel] completed in
            if completed, self?.operationID == id {
                self?.suppressCloseCallback = true
                panel.orderOut(nil)
                self?.suppressCloseCallback = false
                panel.setFrame(finalFrame, display: true)
                panel.alphaValue = 1
            }
        }
        return result
    }

    private func install(notification: DockCatNotification, preferences: DockCatPreferences) {
        let view = NotificationCardView(notification: notification, canDismiss: preferences.transientManuallyDismissible || notification.presentation == .persistent, opensAction: preferences.clickCardOpensAction) { [weak self] in self?.onDismiss?() }
        panel.contentView = NSHostingView(rootView: view)
    }

    private func animate(id: UUID, duration: TimeInterval, animations: @escaping @MainActor () -> Void, completion: @escaping @MainActor (Bool) -> Void) async -> PresentationAnimationResult {
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.allowsImplicitAnimation = true
                animations()
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    let completed = self?.operationID == id && !Task.isCancelled
                    completion(completed)
                    continuation.resume(returning: completed ? .completed : .cancelled)
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) { if !suppressCloseCallback { onDismiss?() } }
}
