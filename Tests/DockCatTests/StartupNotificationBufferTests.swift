import DockCatCore
import XCTest
@testable import DockCat

final class StartupNotificationBufferTests: XCTestCase {
    func testEnablingSubmissionsDrainInOrderOnceRuntimeIsRunning() {
        var buffer = StartupNotificationBuffer()
        let first = notification("first")
        let second = notification("second")

        XCTAssertTrue(buffer.deferIfEnabling(first, runtimeMode: .enabling))
        XCTAssertTrue(buffer.deferIfEnabling(second, runtimeMode: .enabling))
        XCTAssertEqual(buffer.count, 2)
        XCTAssertTrue(buffer.drainIfRunning(runtimeMode: .enabling).isEmpty)
        XCTAssertEqual(buffer.count, 2)

        XCTAssertEqual(
            buffer.drainIfRunning(runtimeMode: .running),
            [first, second]
        )
        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.drainIfRunning(runtimeMode: .running).isEmpty)
    }

    func testOnlyEnablingSubmissionsAreDeferred() {
        for mode in DockCatRuntimeMode.allCases where mode != .enabling {
            var buffer = StartupNotificationBuffer()

            XCTAssertFalse(
                buffer.deferIfEnabling(notification(mode.rawValue), runtimeMode: mode),
                "Unexpectedly deferred a submission while \(mode.rawValue)"
            )
            XCTAssertEqual(buffer.count, 0)
        }
    }

    func testCancelledStartupCanDiscardDeferredSubmissions() {
        var buffer = StartupNotificationBuffer()
        XCTAssertTrue(buffer.deferIfEnabling(notification("queued"), runtimeMode: .enabling))

        buffer.removeAll()

        XCTAssertEqual(buffer.count, 0)
        XCTAssertTrue(buffer.drainIfRunning(runtimeMode: .running).isEmpty)
    }

    private func notification(_ title: String) -> DockCatNotification {
        .init(sourceName: "test", title: title, message: "")
    }
}
