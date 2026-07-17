import AppKit
import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class DockCalibrationPreviewControllerTests: XCTestCase {
    func testPreviewCreatesOnlyTwoIndependentMarkersAndStopsCleanly() {
        let controller = DockCalibrationPreviewController()
        let placement = DockPlacement(
            sleepingPoint: CGPoint(x: 240, y: 120),
            presentationPoint: CGPoint(x: 500, y: 120),
            baseSleepingPoint: CGPoint(x: 240, y: 120),
            basePresentationPoint: CGPoint(x: 500, y: 120),
            edge: .bottom,
            geometryConfidence: .autoHideFallbackEstimate,
            screenFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleScreenFrame: CGRect(x: 0, y: 24, width: 1_440, height: 876),
            displayIdentity: .init(value: "test", quality: .stableUUID),
            displayName: "Test",
            requestedDisplayAvailable: true,
            usedDisplayFallback: false,
            migratedSelection: nil
        )

        controller.start(with: placement)
        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.visibleMarkerCountForTesting, 2)

        controller.update(placement)
        XCTAssertEqual(controller.visibleMarkerCountForTesting, 2)

        controller.stop()
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.visibleMarkerCountForTesting, 0)
    }
}
