import AppKit
import DockCatCore
import Foundation
import ImageIO
import SpriteKit

struct CatFrameImageMetadata: Equatable, Sendable { let pixelWidth: Int; let pixelHeight: Int }

protocol CatAnimationAssetLocating {
    func manifestData() throws -> Data
    func textureAtlas(named: String) throws -> SKTextureAtlas
    func sourceImageMetadata(for frameName: String) throws -> CatFrameImageMetadata
}

enum CatArtworkLoadResult { case loaded(CatAnimationClipLibrary), vectorFallback(CatAssetDiagnosticDetail), unavailableOptionalAtlas }

enum CatAssetDiagnosticDetail: String, Sendable { case manifestMissing, unsupportedSchema, missingRequiredClip, missingFrame, dimensionMismatch, anchorMismatch, atlasLoadFailed, loaded, vectorFallback, malformedManifest }

@MainActor
final class CatAnimationAtlasLoader {
    private let locator: CatAnimationAssetLocating
    private var cached: CatArtworkLoadResult?
    private(set) var loadAttemptsForTesting = 0
    init(locator: CatAnimationAssetLocating = ProductionCatAnimationAssetLocator()) { self.locator = locator }
    func load() -> CatArtworkLoadResult {
        if let cached { return cached }
        loadAttemptsForTesting += 1
        let result = loadUncached()
        if case .loaded = result { cached = result }
        else { cached = result }
        return result
    }
    private func loadUncached() -> CatArtworkLoadResult {
        let data: Data
        do { data = try locator.manifestData() } catch { return .unavailableOptionalAtlas }
        let manifest: CatAnimationAtlasManifest
        do { manifest = try JSONDecoder().decode(CatAnimationAtlasManifest.self, from: data) } catch { return .vectorFallback(.malformedManifest) }
        let validation = CatAnimationManifestValidator.validate(manifest)
        guard validation.isValid else {
            if validation.errors.contains(where: { if case .unsupportedSchema = $0 { return true }; return false }) { return .vectorFallback(.unsupportedSchema) }
            if validation.errors.contains(.incompatibleAnchorContract) { return .vectorFallback(.anchorMismatch) }
            if validation.errors.contains(where: { if case .missingRequiredClip = $0 { return true }; return false }) { return .vectorFallback(.missingRequiredClip) }
            return .vectorFallback(.malformedManifest)
        }
        let atlas: SKTextureAtlas
        do { atlas = try locator.textureAtlas(named: manifest.atlasName) } catch { return .vectorFallback(.atlasLoadFailed) }
        let expected = CatFrameImageMetadata(pixelWidth: Int(manifest.logicalCanvasSize.width) * manifest.nativeScale, pixelHeight: Int(manifest.logicalCanvasSize.height) * manifest.nativeScale)
        var clips: [CatAnimationClipID: CatAnimationClip] = [:]
        for id in CatAnimationClipID.allCases {
            guard let clipManifest = manifest.clips.first(where: { $0.id == id }) else { return .vectorFallback(.missingRequiredClip) }
            var textures: [SKTexture] = []
            for frame in clipManifest.frameNames {
                guard atlas.textureNames.contains(frame) || atlas.textureNames.contains(frame + ".png") else { return .vectorFallback(.missingFrame) }
                guard let metadata = try? locator.sourceImageMetadata(for: frame), metadata == expected else { return .vectorFallback(.dimensionMismatch) }
                let texture = atlas.textureNamed(frame)
                texture.filteringMode = .linear // Illustrated artwork uses interpolation; pixel art should version a new contract.
                textures.append(texture)
            }
            clips[id] = CatAnimationClip(id: id, textures: textures, frameNamesForTesting: clipManifest.frameNames, secondsPerFrame: clipManifest.secondsPerFrame, playback: clipManifest.playback, anchors: manifest.anchors, nativeScale: manifest.nativeScale)
        }
        let allTextures = clips.values.flatMap(\.textures)
        SKTexture.preload(allTextures) {}
        guard let library = CatAnimationClipLibrary(assetSetID: manifest.assetSetID, assetSetVersion: manifest.assetSetVersion, clips: clips) else { return .vectorFallback(.missingRequiredClip) }
        return .loaded(library)
    }
}

struct ProductionCatAnimationAssetLocator: CatAnimationAssetLocating {
    private let bundle: Bundle
    init(bundle: Bundle = .module) { self.bundle = bundle }
    func manifestData() throws -> Data {
        guard let url = bundle.url(forResource: "CatAnimations/manifest", withExtension: "json") ?? bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "CatAnimations") else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }
    func textureAtlas(named: String) throws -> SKTextureAtlas { SKTextureAtlas(named: "CatAnimations/\(named)") }
    func sourceImageMetadata(for frameName: String) throws -> CatFrameImageMetadata {
        guard let url = bundle.url(forResource: frameName, withExtension: "png", subdirectory: "CatAnimations/TestCat.atlas") ?? bundle.url(forResource: frameName, withExtension: nil, subdirectory: "CatAnimations/TestCat.atlas") else { throw CocoaError(.fileNoSuchFile) }
        return try Self.metadata(url: url)
    }
    static func metadata(url: URL) throws -> CatFrameImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { throw CocoaError(.fileReadCorruptFile) }
        return .init(pixelWidth: w, pixelHeight: h)
    }
}
