import XCTest
@testable import DockCatCore

final class DockGeometryTests: XCTestCase {
    let frame = Rect(x: 0, y: 0, width: 1920, height: 1080)
    func testBottomLeftRightAndFallback() {
        XCTAssertEqual(DockGeometryInference.infer(frame: frame, visible: .init(x: 0, y: 70, width: 1920, height: 1010)), .init(edge: .bottom, thickness: 70))
        XCTAssertEqual(DockGeometryInference.infer(frame: frame, visible: .init(x: 80, y: 0, width: 1840, height: 1080)), .init(edge: .left, thickness: 80))
        XCTAssertEqual(DockGeometryInference.infer(frame: frame, visible: .init(x: 0, y: 0, width: 1840, height: 1080)), .init(edge: .right, thickness: 80))
        XCTAssertEqual(
            DockGeometryInference.infer(frame: frame, visible: frame),
            .init(edge: .bottom, thickness: 72, confidence: .autoHideFallbackEstimate)
        )
        XCTAssertGreaterThan(
            DockGeometryInference.infer(frame: frame, visible: frame, fallbackThickness: 0).thickness,
            0
        )
    }

    func testAmbiguousInsetsAreMarkedAsEstimates() {
        let result = DockGeometryInference.infer(
            frame: frame,
            visible: .init(x: 69, y: 70, width: 1_851, height: 1_010)
        )
        XCTAssertEqual(result.edge, .bottom)
        XCTAssertEqual(result.confidence, .ambiguousEstimate)
    }
}
