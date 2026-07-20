import Foundation
import XCTest

final class CatAnimationSourceCatalogTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    func testProductionSourceCatalogIsTextOnlyAndComplete() throws {
        let catalogURL = root.appendingPathComponent("Design/CatAnimations/v1/FRAME-CATALOG.json")
        let data = try Data(contentsOf: catalogURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["assetSetID"] as? String, "dockcat.orange.v1")
        XCTAssertEqual(object["assetSetVersion"] as? String, "1.0.0")
        XCTAssertEqual(object["atlasName"] as? String, "DockCatCat")
        XCTAssertEqual(object["frameCount"] as? Int, 92)
        let clips = try XCTUnwrap(object["clips"] as? [String: [String: Any]])
        XCTAssertEqual(Set(clips.keys), ["sleep", "wake", "pickUp", "turnToPresentation", "walkCarry", "present", "wait", "turnHome", "walkHome", "settle"])
        XCTAssertEqual(clips.values.reduce(0) { $0 + ($1["frames"] as? Int ?? 0) }, 92)
    }

    func testRuntimeBinaryAtlasIsNotCommitted() throws {
        let atlasURL = root.appendingPathComponent("Sources/DockCat/Resources/CatAnimations/DockCatCat.atlas")
        XCTAssertFalse(FileManager.default.fileExists(atPath: atlasURL.path), "binary PNG atlas should be generated locally, not committed")
    }
}
