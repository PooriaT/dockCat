import AppKit
import DockCatCore
import Foundation

@MainActor
protocol AccessibilityDisplayOptionsReading: AnyObject {
    var options: AccessibilityDisplayOptions { get }
}

@MainActor
final class WorkspaceAccessibilityDisplayOptionsReader: AccessibilityDisplayOptionsReading {
    var options: AccessibilityDisplayOptions {
        let workspace = NSWorkspace.shared
        return AccessibilityDisplayOptions(
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        )
    }
}

@MainActor
final class AccessibilityDisplayOptionsMonitor: ObservableObject {
    @Published private(set) var options: AccessibilityDisplayOptions
    var onChange: ((AccessibilityDisplayOptions) -> Void)?

    var reduceMotion: Bool { options.reduceMotion }

    private let reader: AccessibilityDisplayOptionsReading
    private let workspaceNotificationCenter: NotificationCenter
    private let applicationNotificationCenter: NotificationCenter
    private var observations: [NSObjectProtocol] = []

    init(
        reader: AccessibilityDisplayOptionsReading = WorkspaceAccessibilityDisplayOptionsReader(),
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationNotificationCenter: NotificationCenter = .default
    ) {
        self.reader = reader
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.applicationNotificationCenter = applicationNotificationCenter
        options = reader.options
    }

    func start() {
        guard observations.isEmpty else {
            refresh()
            return
        }
        observations.append(workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observations.append(applicationNotificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        refresh()
    }

    func refresh() {
        let newest = reader.options
        guard newest != options else { return }
        options = newest
        onChange?(newest)
    }

    func stop() {
        observations.forEach(workspaceNotificationCenter.removeObserver)
        observations.forEach(applicationNotificationCenter.removeObserver)
        observations.removeAll()
        onChange = nil
    }
}
