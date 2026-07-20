import XCTest
@testable import DockCatCore

final class ApplicationRecoveryCommandTests: XCTestCase {
    func testRecoveryArgumentsParseInDeterministicOrder() throws {
        let commands = try ApplicationRecoveryCommandParser().parse([
            "--show-settings", "--restore-menu-bar", "--show-settings"
        ])
        XCTAssertEqual(commands, [.showSettings, .restoreMenuBar, .showSettings])
    }

    func testUnknownArgumentsCannotTriggerAnyRecoveryMutation() {
        XCTAssertThrowsError(try ApplicationRecoveryCommandParser().parse([
            "--show-settings", "--reset-all-preferences"
        ])) { error in
            XCTAssertEqual(error as? ApplicationRecoveryCommandParseError, .unsupportedArgument)
        }
    }

    func testBootstrapGuardAcceptsExactlyOneStart() {
        var guardState = ApplicationBootstrapGuard()
        XCTAssertTrue(guardState.beginIfNeeded())
        XCTAssertFalse(guardState.beginIfNeeded())
        XCTAssertFalse(guardState.beginIfNeeded())
        XCTAssertTrue(guardState.hasStarted)
    }
}
