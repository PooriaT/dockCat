import AppKit
import DockCatCore
import SwiftUI

@MainActor
final class CardWindowController: NSObject, NSWindowDelegate {
    private let panel = CardOverlayPanel()
    private var anchor = CGPoint.zero
    var onDismiss: (() -> Void)?
    override init() { super.init(); panel.delegate = self }
    func position(above point: CGPoint, offset: Double) {
        anchor = CGPoint(x: point.x - 170, y: point.y + offset + 55)
        if panel.isVisible { panel.setFrameOrigin(anchor) }
    }
    func show(notification: DockCatNotification, preferences: DockCatPreferences) {
        let view = NotificationCardView(notification: notification, canDismiss: preferences.transientManuallyDismissible || notification.presentation == .persistent, opensAction: preferences.clickCardOpensAction) { [weak self] in self?.onDismiss?() }
        panel.contentView = NSHostingView(rootView: view); panel.setFrameOrigin(anchor); panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }
    func windowWillClose(_ notification: Notification) { onDismiss?() }
}
