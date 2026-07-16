import XCTest
@testable import DockCatCore

final class AccessibilityNotificationParserTests: XCTestCase {
    private let parser = AccessibilityNotificationParser()

    func testBannerParsesVisibleFields() throws {
        let candidate = try parser.parse(AXFixtures.banner()).get()
        XCTAssertEqual(candidate.sourceDisplayName.displayValue, "Example Lab")
        XCTAssertEqual(candidate.title.displayValue, "Orbit status")
        XCTAssertEqual(candidate.message.displayValue, "A synthetic task finished.")
        XCTAssertEqual(candidate.structuralKind, .banner)
    }
    func testMissingTitleAndBodyVariantsRemainValid() throws {
        XCTAssertEqual(try parser.parse(AXFixtures.banner(title: nil)).get().title, .missing)
        XCTAssertEqual(try parser.parse(AXFixtures.banner(body: nil)).get().message, .missing)
        let sourceOnly = try parser.parse(AXFixtures.banner(title: nil, body: nil)).get()
        XCTAssertEqual(sourceOnly.sourceDisplayName.displayValue, "Example Lab")
    }
    func testUnrelatedWidgetAndUnknownStructureAreRejected() {
        XCTAssertEqual(parser.parse(AXFixtures.widget), .failure(.unrelatedStructure))
        XCTAssertEqual(parser.parse(AXFixtures.unknown), .failure(.unrelatedStructure))
    }
    func testHiddenPreviewIsRepresentedWithoutInference() throws {
        let candidate = try parser.parse(AXFixtures.hidden).get()
        XCTAssertEqual(candidate.message.displayValue, "Preview hidden")
        XCTAssertEqual(candidate.title, .missing)
        let hiddenTitle = try parser.parse(AXFixtures.hiddenTitle).get()
        XCTAssertEqual(hiddenTitle.title, .missing); XCTAssertEqual(hiddenTitle.message.displayValue, "Visible invented body")
        let hiddenBody = try parser.parse(AXFixtures.hiddenBody).get()
        XCTAssertEqual(hiddenBody.title.displayValue, "Visible invented title"); XCTAssertEqual(hiddenBody.message.displayValue, "Preview hidden")
    }
    func testLocalizedActionLabelsAreMetadataNotParsingSignals() throws {
        let candidate = try parser.parse(AXFixtures.alert).get()
        XCTAssertEqual(candidate.actions.map(\.label), ["Fortfahren", "Schließen"])
    }
    func testWhitespaceAndOversizedValuesAreBounded() throws {
        let parser = AccessibilityNotificationParser(limits: .init(fieldLength: 12, actionCount: 2))
        let value = try parser.parse(AXFixtures.banner(title: "  Invented\n  long   title value ")).get().title.displayValue
        XCTAssertEqual(value, "Invented lon")
    }
    func testEmptyVisibleFieldIsDistinctFromMissing() throws {
        XCTAssertEqual(try parser.parse(AXFixtures.banner(title: "   ")).get().title, .empty)
    }
    func testDockCatOriginIsExcludedByStableBundleOnly() throws {
        let policy = AccessibilityNotificationExclusionPolicy(ownBundleIdentifier: "com.example.DockCat")
        let own = try parser.parse(AXFixtures.banner(bundle: "com.example.DockCat")).get()
        let similarlyNamed = try parser.parse(AXFixtures.banner(source: "DockCat Companion", bundle: "org.example.companion")).get()
        XCTAssertEqual(policy.rejection(for: own), .excludedOrigin)
        XCTAssertNil(policy.rejection(for: similarlyNamed))
    }
}
