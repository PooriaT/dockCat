import AppKit
import DockCatCore
import SpriteKit
import XCTest
@testable import DockCat

@MainActor
final class CatAnimationAtlasLoaderTests: XCTestCase {
    func testMissingManifestSelectsUnavailableOptionalAtlas() {
        let loader = CatAnimationAtlasLoader(locator: FixtureLocator(manifest: nil))
        if case .unavailableOptionalAtlas = loader.load() {} else { XCTFail("expected unavailable") }
    }
    func testValidAtlasLoadsCompleteLibraryAndCaches() throws {
        let manifest = Self.manifest()
        let loader = CatAnimationAtlasLoader(locator: FixtureLocator(manifest: manifest))
        guard case .loaded(let library) = loader.load() else { return XCTFail("expected loaded") }
        XCTAssertEqual(library.assetSetID, "dockcat-test")
        XCTAssertEqual(library[.wake].frameNamesForTesting, ["wake_0", "wake_1"])
        _ = loader.load()
        XCTAssertEqual(loader.loadAttemptsForTesting, 1)
    }
    func testWrongDimensionsAndMissingFrameFallback() {
        if case .vectorFallback(.dimensionMismatch) = CatAnimationAtlasLoader(locator: FixtureLocator(manifest: Self.manifest(), wrongSizeFrame: "sleep_0")).load() {} else { XCTFail("dimension mismatch") }
        if case .vectorFallback(.missingFrame) = CatAnimationAtlasLoader(locator: FixtureLocator(manifest: Self.manifest(), missingFrame: "sleep_0")).load() {} else { XCTFail("missing frame") }
    }
    func testMetadataLookupUsesManifestAtlasName() {
        let locator = FixtureLocator(manifest: Self.manifest(atlasName: "ProductionCat"))
        guard case .loaded = CatAnimationAtlasLoader(locator: locator).load() else { return XCTFail("expected loaded") }
        XCTAssertEqual(locator.requestedAtlasNames, Set(["ProductionCat"]))
    }
    func testSceneUsesTypedClipWhenLibraryInjectedAndFallbackStillRuns() async throws {
        guard case .loaded(let library) = CatAnimationAtlasLoader(locator: FixtureLocator(manifest: Self.manifest())).load() else { return XCTFail("load") }
        let scene = CatScene(size: CGSize(width: 150, height: 110), artworkLoadResult: .loaded(library))
        let result = await scene.runAsync(.wake, duration: 0.1, preferences: .default)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(scene.currentSpriteClipIDForTesting, .wake)
        let fallback = CatScene(size: CGSize(width: 150, height: 110), artworkLoadResult: .unavailableOptionalAtlas)
        XCTAssertFalse(fallback.usesSpriteAtlasForTesting)
        XCTAssertEqual(await fallback.runAsync(.wake, duration: 0.01, preferences: .default), .completed)
    }
    static func manifest(atlasName: String = "TestCat") -> CatAnimationAtlasManifest { Self.valid(atlasName: atlasName, clips: CatAnimationClipID.allCases.map { id in Self.clip(id, frames: id == .wake ? ["wake_0", "wake_1"] : ["\(id.rawValue)_0"]) }) }
    static func valid(atlasName: String = "TestCat", clips: [CatAnimationClipManifest]) -> CatAnimationAtlasManifest { .init(schemaVersion: 1, assetSetID: "dockcat-test", assetSetVersion: "1", atlasName: atlasName, logicalCanvasSize: Size(width: 150, height: 110), nativeScale: 2, anchors: .init(visualAnchor: Point(x: 75, y: 35), feetAnchor: Point(x: 75, y: 35), carryAnchor: Point(x: 117, y: 73), handoffSize: Size(width: 36, height: 24)), orientationPolicy: .canonicalRightFacingMirrorLeftRotateVertical, clips: clips) }
    static func clip(_ id: CatAnimationClipID, frames: [String]) -> CatAnimationClipManifest { .init(id: id, frameNames: frames, secondsPerFrame: 0.1, playback: ([.sleep,.walkCarry,.wait,.walkHome].contains(id) ? .loop : .once), restorePolicy: .preserveFinalFrame) }
}

private final class FixtureLocator: CatAnimationAssetLocating {
    let manifest: CatAnimationAtlasManifest?; var wrongSizeFrame: String? = nil; var missingFrame: String? = nil; private(set) var requestedAtlasNames: Set<String> = []
    init(manifest: CatAnimationAtlasManifest?, wrongSizeFrame: String? = nil, missingFrame: String? = nil) { self.manifest = manifest; self.wrongSizeFrame = wrongSizeFrame; self.missingFrame = missingFrame }
    func manifestData() throws -> Data { guard let manifest else { throw CocoaError(.fileNoSuchFile) }; return try JSONEncoder().encode(manifest) }
    func textureAtlas(named: String) throws -> SKTextureAtlas { TestAtlas(names: names) }
    var names: [String] { guard let manifest else { return [] }; return manifest.clips.flatMap(\.frameNames).filter { $0 != missingFrame } }
    func sourceImageMetadata(for frameName: String, inAtlas atlasName: String) throws -> CatFrameImageMetadata { requestedAtlasNames.insert(atlasName); return frameName == wrongSizeFrame ? .init(pixelWidth: 299, pixelHeight: 220) : .init(pixelWidth: 300, pixelHeight: 220) }
}

private final class TestAtlas: SKTextureAtlas {
    private let namesValue: [String]
    init(names: [String]) { self.namesValue = names; super.init() }
    required init?(coder aDecoder: NSCoder) { nil }
    override var textureNames: [String] { namesValue }
    override func textureNamed(_ name: String) -> SKTexture { SKTexture(image: NSImage(size: NSSize(width: 150, height: 110))) }
}
