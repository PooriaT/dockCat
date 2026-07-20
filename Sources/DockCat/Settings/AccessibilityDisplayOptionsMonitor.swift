import AppKit
import Foundation

@MainActor
protocol AccessibilityDisplayOptionsReading: AnyObject {
    var reduceMotion: Bool { get }
}

@MainActor
final class WorkspaceAccessibilityDisplayOptionsReader: AccessibilityDisplayOptionsReading {
    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

@MainActor
final class AccessibilityDisplayOptionsMonitor: ObservableObject {
    @Published private(set) var reduceMotion: Bool
    var onChange: ((Bool) -> Void)?

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
        reduceMotion = reader.reduceMotion
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
        let newest = reader.reduceMotion
        guard newest != reduceMotion else { return }
        reduceMotion = newest
        onChange?(newest)
    }

    func stop() {
        observations.forEach(workspaceNotificationCenter.removeObserver)
        observations.forEach(applicationNotificationCenter.removeObserver)
        observations.removeAll()
        onChange = nil
    }
}
