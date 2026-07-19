import XCTest
@testable import DockCatCore

final class CatOverlayGeometryTests: XCTestCase {
    func testSupportedScalesHavePaddedOverlayAndScaleOneKeepsExistingContract() {
        let small = CatOverlayGeometry(scale: 0.5)
        let normal = CatOverlayGeometry(scale: 1)
        let large = CatOverlayGeometry(scale: 2)

        XCTAssertGreaterThanOrEqual(
            small.panelSize.width,
            small.scaledArtworkSize.width + small.safetyPadding * 2
        )
        XCTAssertEqual(normal.panelSize, .init(width: 150, height: 110))
        XCTAssertEqual(normal.visualAnchorInPanel, .init(x: 75, y: 35))
        XCTAssertGreaterThanOrEqual(
            large.panelSize.height,
            large.scaledArtworkSize.height + large.safetyPadding * 2
        )
    }

    func testResizePreservesPositiveAndNegativeGlobalAnchors() {
        for anchor in [Point(x: 450, y: 92), Point(x: -850, y: -40)] {
            for scale in [0.5, 1, 2] {
                let geometry = CatOverlayGeometry(scale: scale)
                let origin = geometry.panelOrigin(preservingGlobalVisualAnchor: anchor)
                XCTAssertEqual(geometry.globalVisualAnchor(forPanelOrigin: origin), anchor)
            }
        }
    }

    func testHandoffAndExclusionFramesScaleFromTheSameAnchor() {
        let anchor = Point(x: -400, y: 80)
        let normal = CatOverlayGeometry(scale: 1)
        let large = CatOverlayGeometry(scale: 2)

        XCTAssertEqual(
            normal.handoffFrame(forGlobalVisualAnchor: anchor),
            .init(x: -376, y: 106, width: 36, height: 24)
        )
        XCTAssertEqual(
            large.handoffFrame(forGlobalVisualAnchor: anchor),
            .init(x: -352, y: 132, width: 72, height: 48)
        )
        XCTAssertEqual(large.handoffSize, .init(width: 72, height: 48))
        XCTAssertEqual(
            normal.handoffFrame(forGlobalVisualAnchor: anchor, facing: .left),
            .init(x: -460, y: 106, width: 36, height: 24)
        )
        XCTAssertEqual(
            normal.presentationExclusionFrame(forGlobalVisualAnchor: anchor),
            .init(x: -475, y: 45, width: 150, height: 110)
        )
    }
}
