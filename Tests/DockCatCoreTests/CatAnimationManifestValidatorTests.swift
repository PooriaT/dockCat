import DockCatCore
import XCTest

final class CatAnimationManifestValidatorTests: XCTestCase {
    func testSupportedManifestValidatesAndResolverMapsSemantics() {
        XCTAssertTrue(CatAnimationManifestValidator.validate(Self.valid()).isValid)
        XCTAssertEqual(CatAnimationClipResolver.clipID(for: .walkToPresentationLoop(Self.context())), .walkCarry)
        XCTAssertEqual(CatAnimationClipResolver.clipID(for: .stopAtPresentation(Self.context())), .present)
        XCTAssertNil(CatAnimationClipResolver.clipID(for: .walkToPresentation))
        XCTAssertNil(CatAnimationClipResolver.clipID(for: .walkHome))
    }
    func testValidationCategories() {
        assert(Self.valid(schema: 2), .unsupportedSchema(2))
        var m = Self.valid(clips: Self.clips().filter { $0.id != .sleep }); assert(m, .missingRequiredClip(.sleep))
        m = Self.valid(clips: Self.clips() + [Self.clip(.sleep)]); assert(m, .duplicateClip(.sleep))
        m = Self.valid(clips: Self.clips(replacing: .sleep, with: Self.clip(.sleep, frames: []))); assert(m, .emptyFrameList(.sleep))
        m = Self.valid(clips: Self.clips(replacing: .sleep, with: Self.clip(.sleep, frames: ["a", "a"]))); assert(m, .duplicateFrameName(.sleep, "a"))
        m = Self.valid(clips: Self.clips(replacing: .sleep, with: Self.clip(.sleep, frames: ["../bad"] ))); assert(m, .invalidFrameBasename(.sleep, "../bad"))
        m = Self.valid(clips: Self.clips(replacing: .sleep, with: Self.clip(.sleep, seconds: 0))); assert(m, .invalidDuration(.sleep))
        m = Self.valid(clips: Self.clips(replacing: .sleep, with: Self.clip(.sleep, playback: .once))); assert(m, .invalidPlaybackMode(.sleep))
        m = Self.valid(size: Size(width: 1, height: 110)); assert(m, .invalidCanvas)
        m = Self.valid(anchors: .init(visualAnchor: Point(x: 1, y: 35), feetAnchor: Point(x: 75, y: 35), carryAnchor: Point(x: 117, y: 73), handoffSize: Size(width: 36, height: 24))); assert(m, .incompatibleAnchorContract)
        m = Self.valid(scale: 0); assert(m, .invalidScale)
    }
    private func assert(_ manifest: CatAnimationAtlasManifest, _ error: CatAnimationManifestValidationError, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(CatAnimationManifestValidator.validate(manifest).errors.contains(error), file: file, line: line)
    }
    static func valid(schema: Int = 1, size: Size = Size(width: 150, height: 110), scale: Int = 2, anchors: CatAtlasAnchorManifest = .init(visualAnchor: Point(x: 75, y: 35), feetAnchor: Point(x: 75, y: 35), carryAnchor: Point(x: 117, y: 73), handoffSize: Size(width: 36, height: 24)), clips: [CatAnimationClipManifest] = clips()) -> CatAnimationAtlasManifest { .init(schemaVersion: schema, assetSetID: "dockcat-test", assetSetVersion: "1", atlasName: "TestCat", logicalCanvasSize: size, nativeScale: scale, anchors: anchors, orientationPolicy: .canonicalRightFacingMirrorLeftRotateVertical, clips: clips) }
    static func clips(replacing id: CatAnimationClipID? = nil, with replacement: CatAnimationClipManifest? = nil) -> [CatAnimationClipManifest] { CatAnimationClipID.allCases.map { $0 == id ? replacement! : clip($0) } }
    static func clip(_ id: CatAnimationClipID, frames: [String]? = nil, seconds: Double = 0.1, playback: CatClipPlayback? = nil) -> CatAnimationClipManifest { .init(id: id, frameNames: frames ?? ["\(id.rawValue)_0"], secondsPerFrame: seconds, playback: playback ?? ([.sleep,.walkCarry,.wait,.walkHome].contains(id) ? .loop : .once), restorePolicy: .preserveFinalFrame) }
    static func context() -> CatAnimationContext { .init(dockEdge: .bottom, direction: .right, purpose: .presentation, phase: .walking, facing: .right, isCarryingMiniCard: true, reducedMotion: false) }
}
