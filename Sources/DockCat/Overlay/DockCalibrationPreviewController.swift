import AppKit
import DockCatCore
import OSLog

@MainActor
final class DockCalibrationPreviewController {
    private let homePanel = DockCalibrationPreviewPanel(
        title: "Home", color: .systemBlue, accessibilityLabel: "DockCat home anchor preview"
    )
    private let presentationPanel = DockCalibrationPreviewPanel(
        title: "Presentation", color: .systemOrange,
        accessibilityLabel: "DockCat presentation anchor preview"
    )
    private let logger = Logger(subsystem: "com.example.DockCat", category: "CalibrationPreview")
    private(set) var isActive = false

    func start(with placement: DockPlacement) {
        isActive = true
        update(placement)
        homePanel.orderFrontRegardless()
        presentationPanel.orderFrontRegardless()
        logger.info("Calibration preview started")
    }

    func update(_ placement: DockPlacement) {
        guard isActive else { return }
        homePanel.center(on: placement.sleepingPoint, within: placement.visibleScreenFrame)
        presentationPanel.center(on: placement.presentationPoint, within: placement.visibleScreenFrame)
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        homePanel.orderOut(nil)
        presentationPanel.orderOut(nil)
        logger.info("Calibration preview stopped")
    }

    var visibleMarkerCountForTesting: Int {
        [homePanel, presentationPanel].filter(\.isVisible).count
    }
}

private final class DockCalibrationPreviewPanel: NSPanel {
    private static let markerSize = CGSize(width: 124, height: 38)

    init(title: String, color: NSColor, accessibilityLabel: String) {
        super.init(
            contentRect: CGRect(origin: .zero, size: Self.markerSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false

        let label = NSTextField(labelWithString: title)
        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.wantsLayer = true
        label.layer?.backgroundColor = color.withAlphaComponent(0.92).cgColor
        label.layer?.cornerRadius = 10
        label.frame = CGRect(origin: .zero, size: Self.markerSize)
        label.setAccessibilityLabel(accessibilityLabel)
        contentView = label
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func center(on point: CGPoint, within visibleFrame: CGRect) {
        let proposed = CGPoint(
            x: point.x - Self.markerSize.width / 2,
            y: point.y - Self.markerSize.height / 2
        )
        let x = min(
            visibleFrame.maxX - Self.markerSize.width,
            max(visibleFrame.minX, proposed.x)
        )
        let y = min(
            visibleFrame.maxY - Self.markerSize.height,
            max(visibleFrame.minY, proposed.y)
        )
        setFrameOrigin(CGPoint(x: x, y: y))
    }
}
