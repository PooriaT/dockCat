import XCTest
@testable import DockCatCore

final class DockCatURLCommandParserTests: XCTestCase {
    private let parser = DockCatURLCommandParser(defaultDuration: 7)

    func testExistingTransientAndPersistentNotificationsStillParse() throws {
        let transient = try parser.parse(URL(string: "dockcat://notify?title=Done&type=transient&duration=4")!)
        guard case .notify(let transientNotification) = transient else {
            return XCTFail("Expected notification command")
        }
        XCTAssertEqual(transientNotification.presentation, .transient(duration: 4))

        let persistent = try parser.parse(URL(string: "dockcat://notify?title=Failed&type=persistent")!)
        guard case .notify(let persistentNotification) = persistent else {
            return XCTFail("Expected notification command")
        }
        XCTAssertEqual(persistentNotification.presentation, .persistent)
    }

    func testSettingsCommandsCannotCreateNotifications() throws {
        XCTAssertEqual(
            try parser.parse(URL(string: "dockcat://settings")!),
            .openSettings(restoreMenuBar: false)
        )
        XCTAssertEqual(
            try parser.parse(URL(string: "dockcat://settings?restoreMenuBar=1")!),
            .openSettings(restoreMenuBar: true)
        )
        XCTAssertEqual(
            try parser.parse(URL(string: "dockcat://restore-menu-bar")!),
            .restoreMenuBar
        )
    }

    func testBooleanAndUnknownInputValidationUsesTypedPrivateFreeErrors() {
        assertError("dockcat://settings?restoreMenuBar=yes", equals: .invalidBoolean)
        assertError("dockcat://settings?other=1", equals: .unknownQueryKey)
        assertError("dockcat://restore-menu-bar?allPreferences=1", equals: .unknownQueryKey)
        assertError("dockcat://unknown?secret=value", equals: .unsupportedCommand)
        assertError("https://settings?secret=value", equals: .unsupportedScheme)
    }

    func testCaseNormalizationAndPercentEncoding() throws {
        XCTAssertEqual(
            try parser.parse(URL(string: "DOCKCAT://SETTINGS?RESTOREMENUBAR=TrUe")!),
            .openSettings(restoreMenuBar: true)
        )
        let command = try parser.parse(
            URL(string: "dockcat://NOTIFY?TITLE=Caf%C3%A9%20%26%20Done&MESSAGE=A%2BB")!
        )
        guard case .notify(let notification) = command else {
            return XCTFail("Expected notification command")
        }
        XCTAssertEqual(notification.title, "Café & Done")
        XCTAssertEqual(notification.message, "A+B")
    }

    func testUnsafeNotificationActionAndUnknownKeysRemainRejected() {
        assertError("dockcat://notify?title=x&action=http%3A%2F%2Fexample.com", equals: .invalidNotification)
        assertError("dockcat://notify?title=x&action=https%3Afoo", equals: .invalidNotification)
        assertError("dockcat://notify?title=x&restoreMenuBar=1", equals: .unknownQueryKey)
    }

    private func assertError(
        _ rawURL: String,
        equals expected: DockCatURLCommandParseError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try parser.parse(URL(string: rawURL)!)) { error in
            XCTAssertEqual(error as? DockCatURLCommandParseError, expected, file: file, line: line)
            XCTAssertFalse(String(describing: error).contains("secret"), file: file, line: line)
        }
    }
}
