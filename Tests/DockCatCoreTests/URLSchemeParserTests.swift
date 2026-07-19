import XCTest
@testable import DockCatCore

final class URLSchemeParserTests: XCTestCase {
    let parser = URLSchemeParser()
    func testValidTransientAndPersistent() throws {
        let transient = try parser.parse(URL(string: "dockcat://notify?title=Done&message=Built&source=Codex&type=transient&duration=4")!)
        XCTAssertEqual(transient.presentation, .transient(duration: 4))
        let persistent = try parser.parse(URL(string: "dockcat://notify?title=Failed&type=persistent")!)
        XCTAssertEqual(persistent.presentation, .persistent)
    }
    func testValidation() {
        XCTAssertThrowsError(try parser.parse(URL(string: "https://notify?title=x")!))
        XCTAssertThrowsError(try parser.parse(URL(string: "dockcat://notify?message=x")!))
        XCTAssertThrowsError(try parser.parse(URL(string: "dockcat://notify?title=x&duration=999")!))
        XCTAssertThrowsError(try parser.parse(URL(string: "dockcat://notify?title=x&action=file:///tmp/x")!))
        XCTAssertThrowsError(try parser.parse(URL(string: "dockcat://notify?title=\(String(repeating: "x", count: 121))")!))
        XCTAssertThrowsError(try parser.parse(URL(string: "dockcat://notify?title=x&unknown=y")!))
        XCTAssertThrowsError(try parser.parse(URL(string: "dockcat://notify?title=x&title=y")!))
    }
}
