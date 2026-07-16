import XCTest
@testable import DockCatCore

final class SystemNotificationSourceHealthTests: XCTestCase {
    func testSystemNotificationsPreferenceDefaultsOffAndLegacyJSONMigrates() throws {
        XCTAssertFalse(DockCatPreferences().systemNotificationsEnabled)
        let legacy = Data(#"{"enabled":false,"queueLimit":7}"#.utf8)
        let decoded = try JSONDecoder().decode(DockCatPreferences.self, from: legacy)
        XCTAssertFalse(decoded.systemNotificationsEnabled)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.queueLimit, 7)
    }

    func testStateSemantics() {
        let disabled = SystemNotificationSourceHealth(.disabled)
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertTrue(disabled.isTerminal)
        XCTAssertFalse(disabled.isHealthy)

        let active = SystemNotificationSourceHealth(.active)
        XCTAssertTrue(active.isEnabled)
        XCTAssertTrue(active.isHealthy)
        XCTAssertFalse(active.isRetryable)

        XCTAssertTrue(SystemNotificationSourceHealth(.permissionRequired, reason: .permissionMissing).isRetryable)
        XCTAssertTrue(SystemNotificationSourceHealth(.degraded, reason: .compatibilityProblem).isRetryable)
        XCTAssertTrue(SystemNotificationSourceHealth(.unavailable, reason: .observerNotImplemented).isRetryable)
    }
}
