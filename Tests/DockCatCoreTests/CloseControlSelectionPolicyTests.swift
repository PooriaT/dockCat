import XCTest
@testable import DockCatCore

final class CloseControlSelectionPolicyTests: XCTestCase {
    private let policy = CloseControlSelectionPolicy()
    private func control(identifier: String? = "notification.close", label: String? = nil, press: Bool = true) -> CloseControlDescriptor {
        .init(path: [0], role: "AXButton", subrole: nil, identifier: identifier, localizedLabel: label,
              supportsPress: press, isDescendantOfNotification: true)
    }
    func testStrongStableEvidenceSelectsClose() { XCTAssertEqual(policy.select(from: [control()]), .selected(control())) }
    func testEnglishTitleAloneIsInsufficient() { XCTAssertEqual(policy.select(from: [control(identifier: nil, label: "Close")]), .rejected) }
    func testUnsafeAndNonPressControlsAreRejected() {
        for identifier in ["reply", "open", "options", "destructive-action", "content-action"] {
            XCTAssertEqual(policy.select(from: [control(identifier: identifier)]), .rejected)
        }
        XCTAssertEqual(policy.select(from: [control(press: false)]), .rejected)
    }
    func testMultipleCloseCandidatesAreAmbiguous() {
        XCTAssertEqual(policy.select(from: [control(), control(identifier: "dismiss-button")]), .ambiguous)
    }
}
