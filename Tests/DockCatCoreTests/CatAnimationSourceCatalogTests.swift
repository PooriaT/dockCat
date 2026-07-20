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

    func testRuntimeBinaryAtlasIsNotGitTracked() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "ls-files", "--", "Sources/DockCat/Resources/CatAnimations/DockCatCat.atlas", "Sources/DockCat/Resources/CatAnimations/manifest.json", "Sources/DockCat/Resources/CatAnimations/ASSET-SOURCES.json"]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "generated runtime atlas files should remain untracked so local exports do not break tests")
    }
}
