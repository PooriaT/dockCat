import AppKit
import XCTest
@testable import DockCat

@MainActor
final class AccessibilityDisplayOptionsMonitorTests: XCTestCase {
    func testPublishedReduceMotionChangesFromWorkspaceNotification() async {
        let reader = DisplayOptionsReaderFake(reduceMotion: false)
        let workspaceCenter = NotificationCenter()
        let appCenter = NotificationCenter()
        let monitor = AccessibilityDisplayOptionsMonitor(
            reader: reader,
            workspaceNotificationCenter: workspaceCenter,
            applicationNotificationCenter: appCenter
        )
        var values: [Bool] = []
        monitor.onChange = { values.append($0) }
        monitor.start()

        reader.reduceMotion = true
        workspaceCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        await Task.yield()

        XCTAssertTrue(monitor.reduceMotion)
        XCTAssertEqual(values, [true])
        monitor.stop()
    }

    func testBecomingActiveRefreshesAndStopRemovesObservation() async {
        let reader = DisplayOptionsReaderFake(reduceMotion: false)
        let workspaceCenter = NotificationCenter()
        let appCenter = NotificationCenter()
        let monitor = AccessibilityDisplayOptionsMonitor(
            reader: reader,
            workspaceNotificationCenter: workspaceCenter,
            applicationNotificationCenter: appCenter
        )
        monitor.start()
        reader.reduceMotion = true
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertTrue(monitor.reduceMotion)

        monitor.stop()
        reader.reduceMotion = false
        appCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await Task.yield()
        XCTAssertTrue(monitor.reduceMotion)
    }
}

@MainActor
private final class DisplayOptionsReaderFake: AccessibilityDisplayOptionsReading {
    var reduceMotion: Bool
    init(reduceMotion: Bool) { self.reduceMotion = reduceMotion }
}
