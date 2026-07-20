import Foundation

public struct CatAnimationManifestValidationResult: Equatable, Sendable {
    public let errors: [CatAnimationManifestValidationError]
    public var isValid: Bool { errors.isEmpty }
    public static let maxErrors = 32
}

public enum CatAnimationManifestValidationError: Equatable, Sendable {
    case unsupportedSchema(Int), malformedAssetSetIdentifier, missingRequiredClip(CatAnimationClipID), duplicateClip(CatAnimationClipID), emptyFrameList(CatAnimationClipID), duplicateFrameName(CatAnimationClipID, String), duplicateFrameOwner(String), invalidFrameBasename(CatAnimationClipID, String), invalidDuration(CatAnimationClipID), invalidPlaybackMode(CatAnimationClipID), invalidCanvas, incompatibleAnchorContract, invalidScale, unsupportedOrientationPolicy
}

public enum CatAnimationManifestValidator {
    public static let supportedSchemaVersion = 1
    public static let durationRange = (1.0 / 120.0)...2.0
    private static let validName = try! NSRegularExpression(pattern: "^[A-Za-z0-9][A-Za-z0-9_.@-]*$")
    public static func validate(_ manifest: CatAnimationAtlasManifest) -> CatAnimationManifestValidationResult {
        var errors: [CatAnimationManifestValidationError] = []
        func add(_ e: CatAnimationManifestValidationError) { if errors.count < CatAnimationManifestValidationResult.maxErrors { errors.append(e) } }
        if manifest.schemaVersion != supportedSchemaVersion { add(.unsupportedSchema(manifest.schemaVersion)) }
        if !isIdentifier(manifest.assetSetID) || manifest.assetSetVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isIdentifier(manifest.atlasName) { add(.malformedAssetSetIdentifier) }
        if manifest.nativeScale < 1 || manifest.nativeScale > 4 { add(.invalidScale) }
        if !finitePositive(manifest.logicalCanvasSize.width) || !finitePositive(manifest.logicalCanvasSize.height) || manifest.logicalCanvasSize != CatOverlayGeometry.basePanelSize { add(.invalidCanvas) }
        if manifest.orientationPolicy != .canonicalRightFacingMirrorLeftRotateVertical { add(.unsupportedOrientationPolicy) }
        if !anchorsMatch(manifest) { add(.incompatibleAnchorContract) }
        var clipIDs = Set<CatAnimationClipID>()
        for clip in manifest.clips {
            if !clipIDs.insert(clip.id).inserted { add(.duplicateClip(clip.id)) }
        }
        for id in CatAnimationClipID.allCases where !clipIDs.contains(id) { add(.missingRequiredClip(id)) }
        var frameOwners: [String: CatAnimationClipID] = [:]
        for clip in manifest.clips.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            if clip.frameNames.isEmpty { add(.emptyFrameList(clip.id)) }
            if !durationRange.contains(clip.secondsPerFrame) || !clip.secondsPerFrame.isFinite { add(.invalidDuration(clip.id)) }
            if requiredPlayback(for: clip.id) != clip.playback && !(transitionIDs.contains(clip.id) && clip.playback == .holdLastFrame) { add(.invalidPlaybackMode(clip.id)) }
            var names = Set<String>()
            for name in clip.frameNames {
                if !isBasename(name) { add(.invalidFrameBasename(clip.id, name)) }
                if !names.insert(name).inserted { add(.duplicateFrameName(clip.id, name)) }
                if let owner = frameOwners[name], owner != clip.id { add(.duplicateFrameOwner(name)) } else { frameOwners[name] = clip.id }
            }
        }
        return .init(errors: errors)
    }
    private static let transitionIDs: Set<CatAnimationClipID> = [.wake, .pickUp, .turnToPresentation, .present, .turnHome, .settle]
    private static func requiredPlayback(for id: CatAnimationClipID) -> CatClipPlayback { [.sleep, .walkCarry, .wait, .walkHome].contains(id) ? .loop : .once }
    private static func finitePositive(_ v: Double) -> Bool { v.isFinite && v > 0 }
    private static func isIdentifier(_ s: String) -> Bool { isBasename(s) && !s.isEmpty }
    private static func isBasename(_ s: String) -> Bool {
        guard !s.isEmpty, !s.hasPrefix("/"), !s.contains(".."), !s.contains("/") && !s.contains("\\") else { return false }
        return validName.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    private static func anchorsMatch(_ m: CatAnimationAtlasManifest) -> Bool {
        let carry = Point(x: CatOverlayGeometry.baseVisualAnchor.x + CatOverlayGeometry.baseCarryOffset.x, y: CatOverlayGeometry.baseVisualAnchor.y + CatOverlayGeometry.baseCarryOffset.y)
        return m.anchors.visualAnchor == CatOverlayGeometry.baseVisualAnchor && m.anchors.feetAnchor == CatOverlayGeometry.baseVisualAnchor && m.anchors.carryAnchor == carry && m.anchors.handoffSize == CatOverlayGeometry.baseHandoffSize && inside(m.anchors.visualAnchor, m.logicalCanvasSize) && inside(m.anchors.carryAnchor, m.logicalCanvasSize)
    }
    private static func inside(_ p: Point, _ s: Size) -> Bool { p.x >= -0.5 && p.y >= -0.5 && p.x <= s.width + 0.5 && p.y <= s.height + 0.5 }
}
