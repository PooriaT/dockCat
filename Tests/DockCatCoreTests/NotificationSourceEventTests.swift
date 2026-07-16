import XCTest
@testable import DockCatCore

final class NotificationSourceEventTests: XCTestCase {
    func testTypedBoundaryKeepsNotificationsAndCandidatesDistinct() {
        let notification = DockCatNotification(sourceName: "test", title: "title", message: "body", presentation: .persistent)
        let snapshot = AccessibilityNotificationSnapshot(origin: .init(bundleIdentifier: "com.apple.notificationcenterui", processIdentifier: 42),
            observationKind: .created, captureSequence: 1, root: .init(role: "AXGroup"))
        XCTAssertEqual(NotificationSourceEvent.notification(notification), .notification(notification))
        XCTAssertEqual(NotificationSourceEvent.accessibilitySnapshot(snapshot), .accessibilitySnapshot(snapshot))
    }
}
