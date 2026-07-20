import AppKit
import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class AccessibilityDisplayOptionsMonitorTests: XCTestCase {
    func testPublishedReduceMotionChangesFromWorkspaceNotification() async {
        let reader = DisplayOptionsReaderFake(options: .standard)
        let workspaceCenter = NotificationCenter()
        let appCenter = NotificationCenter()
        let monitor = AccessibilityDisplayOptionsMonitor(
            reader: reader,
            workspaceNotificationCenter: workspaceCenter,
            applicationNotificationCenter: appCenter
        )
        var values: [AccessibilityDisplayOptions] = []
        monitor.onChange = { values.append($0) }
        monitor.start()

        reader.options = .init(
            reduceMotion: true,
            increaseContrast: true,
            reduceTransparency: true,
            differentiateWithoutColor: true
        )
        workspaceCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        await Task.yield()

        XCTAssertEqual(monitor.options, reader.options)
        XCTAssertEqual(values, [reader.options])
        monitor.stop()
    }

    func testBecomingActiveRefreshesAndStopRemovesObservation() async {
        let reader = DisplayOptionsReaderFake(options: .standard)
        let workspaceCenter = NotificationCenter()
        let appCenter = NotificationCenter()
        let monitor = AccessibilityDisplayOptionsMonitor(
            reader: reader,
            workspaceNotificationCenter: workspaceCenter,
            applicationNotificationCenter: appCenter
        )
        monitor.start()
        reader.options = .init(
            reduceMotion: true,
            increaseContrast: false,
            reduceTransparency: false,
            differentiateWithoutColor: false
        )
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertTrue(monitor.reduceMotion)

        monitor.stop()
        reader.options = .standard
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertTrue(monitor.reduceMotion)
    }
}

@MainActor
private final class DisplayOptionsReaderFake: AccessibilityDisplayOptionsReading {
    var options: AccessibilityDisplayOptions
    init(options: AccessibilityDisplayOptions) { self.options = options }
}
