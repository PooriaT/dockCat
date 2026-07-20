import AppKit

final class CardOverlayPanel: NSPanel {
    private(set) var isInteractive = false
    var activeCardIsDismissible = false
    var onPointerIntent: (() -> Void)?
    var onCancelRequested: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 150), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = true; level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { isInteractive }
    override var canBecomeMain: Bool { false }

    func enterInteractiveMode() {
        isInteractive = true
    }

    func returnToPassiveMode() {
        isInteractive = false
        if isKeyWindow { resignKey() }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { onPointerIntent?() }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        guard isInteractive, isKeyWindow, activeCardIsDismissible else { return }
        onCancelRequested?()
    }
}
