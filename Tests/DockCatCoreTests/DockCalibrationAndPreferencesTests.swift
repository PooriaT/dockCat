import Foundation
import XCTest
@testable import DockCatCore

final class DockCalibrationAndPreferencesTests: XCTestCase {
    private let frame = Rect(x: 100, y: 50, width: 1_400, height: 900)

    func testCalibrationCoordinateSemanticsForEveryDockEdge() {
        let input = Point(x: 500, y: 300)
        let offset = DockAnchorCalibration(alongDock: 25, awayFromDock: 10)
        XCTAssertEqual(
            DockPlacementPlanner.apply(offset, to: input, edge: .bottom),
            .init(x: 525, y: 310)
        )
        XCTAssertEqual(
            DockPlacementPlanner.apply(offset, to: input, edge: .left),
            .init(x: 510, y: 325)
        )
        XCTAssertEqual(
            DockPlacementPlanner.apply(offset, to: input, edge: .right),
            .init(x: 490, y: 325)
        )
    }

    func testHomePresentationAreIndependentAndBaseOffsetsAreAppliedOnce() {
        let geometry = InferredDockGeometry(edge: .bottom, thickness: 70)
        let uncalibrated = DockPlacementPlanner.plan(
            frame: frame, geometry: geometry, sleepingCorner: .end,
            positionOffset: 8, dockEndOffset: 12, calibration: .init()
        )
        let calibrated = DockPlacementPlanner.plan(
            frame: frame, geometry: geometry, sleepingCorner: .end,
            positionOffset: 8, dockEndOffset: 12,
            calibration: .init(
                home: .init(alongDock: 20, awayFromDock: 5),
                presentation: .init(alongDock: -30, awayFromDock: 15)
            )
        )
        XCTAssertEqual(calibrated.baseSleepingPoint, uncalibrated.sleepingPoint)
        XCTAssertEqual(calibrated.basePresentationPoint, uncalibrated.presentationPoint)
        XCTAssertEqual(calibrated.sleepingPoint.x, uncalibrated.sleepingPoint.x + 20)
        XCTAssertEqual(calibrated.sleepingPoint.y, uncalibrated.sleepingPoint.y + 5)
        XCTAssertEqual(calibrated.presentationPoint.x, uncalibrated.presentationPoint.x - 30)
        XCTAssertEqual(calibrated.presentationPoint.y, uncalibrated.presentationPoint.y + 15)
    }

    func testCalibrationIsIsolatedByDisplayAndEdgeAndCanReset() {
        let first = DisplayIdentity(value: "first", quality: .stableUUID)
        let second = DisplayIdentity(value: "second", quality: .stableUUID)
        let calibration = DockCalibration(home: .init(alongDock: 40))
        var preferences = DockCatPreferences()
        preferences.setCalibration(calibration, for: first, edge: .bottom)

        XCTAssertEqual(preferences.calibration(for: first, edge: .bottom), calibration)
        XCTAssertEqual(preferences.calibration(for: first, edge: .left), .init())
        XCTAssertEqual(preferences.calibration(for: second, edge: .bottom), .init())

        preferences.resetCalibration(for: first, edge: .bottom)
        XCTAssertEqual(preferences.calibration(for: first, edge: .bottom), .init())
        XCTAssertTrue(preferences.dockCalibrations.isEmpty)
    }

    func testCalibrationValuesAreBounded() {
        let value = DockAnchorCalibration(
            alongDock: 10_000, awayFromDock: -10_000
        )
        XCTAssertEqual(value.alongDock, DockAnchorCalibration.alongDockRange.upperBound)
        XCTAssertEqual(value.awayFromDock, DockAnchorCalibration.awayFromDockRange.lowerBound)
        let nonFinite = DockAnchorCalibration(alongDock: .infinity, awayFromDock: .nan)
        XCTAssertEqual(nonFinite, .init())
        var mutated = DockAnchorCalibration()
        mutated.alongDock = -9_000
        mutated.awayFromDock = 9_000
        XCTAssertEqual(mutated.alongDock, DockAnchorCalibration.alongDockRange.lowerBound)
        XCTAssertEqual(mutated.awayFromDock, DockAnchorCalibration.awayFromDockRange.upperBound)
    }

    func testOldDisplayStringsDecodeAndNewEncodingUsesTypedModel() throws {
        for (legacy, expected) in [
            ("automatic", DisplaySelection.automatic),
            ("main", DisplaySelection.main),
            ("42", DisplaySelection.specific(.legacy("42"))),
            ("Studio Display", DisplaySelection.specific(.legacy("Studio Display")))
        ] {
            let data = Data("{\"displaySelection\":\"\(legacy)\",\"queueLimit\":37,\"catScale\":1.25}".utf8)
            let decoded = try JSONDecoder().decode(DockCatPreferences.self, from: data)
            XCTAssertEqual(decoded.displaySelection, expected)
            XCTAssertEqual(decoded.queueLimit, 37)
            XCTAssertEqual(decoded.catScale, 1.25)
            XCTAssertTrue(decoded.dockCalibrations.isEmpty)

            let encoded = try JSONEncoder().encode(decoded)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            XCTAssertTrue(object["displaySelection"] is [String: Any])
        }
    }

    func testDuplicateAndCorruptCalibrationRecordsNormalizeWithoutLosingPreferences() throws {
        let json = """
        {
          "queueLimit": 41,
          "nativeBannerDismissalExcludedBundleIdentifiers": [" COM.Example.App "],
          "dockCalibrations": [
            {
              "displayIdentity": {"value":"stable","quality":"stableUUID"},
              "dockEdge":"bottom",
              "calibration":{"home":{"alongDock":10,"awayFromDock":0},"presentation":{"alongDock":0,"awayFromDock":0}}
            },
            {"displayIdentity": 12, "dockEdge":"future", "calibration":"bad"},
            {
              "displayIdentity": {"value":"stable","quality":"stableUUID"},
              "dockEdge":"bottom",
              "calibration":{"home":{"alongDock":25,"awayFromDock":0},"presentation":{"alongDock":0,"awayFromDock":0}}
            }
          ]
        }
        """
        let preferences = try JSONDecoder().decode(
            DockCatPreferences.self, from: Data(json.utf8)
        )
        XCTAssertEqual(preferences.queueLimit, 41)
        XCTAssertEqual(preferences.nativeBannerDismissalExcludedBundleIdentifiers, ["com.example.app"])
        XCTAssertEqual(preferences.dockCalibrations.count, 1)
        XCTAssertEqual(preferences.dockCalibrations[0].calibration.home.alongDock, 25)
    }

    func testCalibrationEncodingOrderIsDeterministic() throws {
        let a = DisplayIdentity(value: "a", quality: .stableUUID)
        let b = DisplayIdentity(value: "b", quality: .stableUUID)
        var first = DockCatPreferences()
        first.setCalibration(.init(home: .init(alongDock: 1)), for: b, edge: .right)
        first.setCalibration(.init(home: .init(alongDock: 2)), for: a, edge: .bottom)
        var second = DockCatPreferences()
        second.setCalibration(.init(home: .init(alongDock: 2)), for: a, edge: .bottom)
        second.setCalibration(.init(home: .init(alongDock: 1)), for: b, edge: .right)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(first), try encoder.encode(second))
    }
}
