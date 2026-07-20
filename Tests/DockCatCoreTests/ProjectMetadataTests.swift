import XCTest
@testable import DockCatCore

final class ProjectMetadataTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    func testInfoPlistUsesBuildSettingsAndURLScheme() throws {
        let plist = try String(contentsOf: root.appendingPathComponent("DockCat/Info.plist"))
        XCTAssertTrue(plist.contains("$(PRODUCT_BUNDLE_IDENTIFIER)")); XCTAssertTrue(plist.contains("$(PRODUCT_NAME)")); XCTAssertTrue(plist.contains("$(MARKETING_VERSION)")); XCTAssertTrue(plist.contains("dockcat"))
    }
    func testProjectMetadata() throws {
        let pbx = try String(contentsOf: root.appendingPathComponent("DockCat.xcodeproj/project.pbxproj"))
        XCTAssertFalse(pbx.contains("com.example" + ".DockCat")); XCTAssertTrue(pbx.contains("PRODUCT_BUNDLE_IDENTIFIER = io.github.pooriat.DockCat")); XCTAssertTrue(pbx.contains("PRODUCT_NAME = DockCat")); XCTAssertTrue(pbx.contains("MARKETING_VERSION = 0.1.0")); XCTAssertTrue(pbx.contains("CURRENT_PROJECT_VERSION = 1")); XCTAssertTrue(pbx.contains("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon")); XCTAssertTrue(pbx.contains("ENABLE_HARDENED_RUNTIME = YES")); XCTAssertFalse(pbx.contains("CODE_SIGN_ENTITLEMENTS")); XCTAssertTrue(pbx.contains("DEVELOPMENT_TEAM = \"\""))
    }
    func testAppIconCatalogComplete() throws {
        let dir = root.appendingPathComponent("Sources/DockCat/Resources/Assets.xcassets/AppIcon.appiconset")
        let contents = try String(contentsOf: dir.appendingPathComponent("Contents.json"))
        for size in [16,32,64,128,256,512,1024] { XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("AppIcon-\(size).svg").path)); XCTAssertTrue(contents.contains("AppIcon-\(size).svg")) }
    }
}
