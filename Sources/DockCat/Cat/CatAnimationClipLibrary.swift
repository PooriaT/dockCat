import DockCatCore
import Foundation
import SpriteKit

@MainActor
struct CatAnimationClip {
    let id: CatAnimationClipID
    let textures: [SKTexture]
    let frameNamesForTesting: [String]
    let secondsPerFrame: TimeInterval
    let playback: CatClipPlayback
    let anchors: CatAtlasAnchorManifest
    let nativeScale: Int
}

@MainActor
struct CatAnimationClipLibrary {
    let assetSetID: String
    let assetSetVersion: String
    private let clips: [CatAnimationClipID: CatAnimationClip]
    init?(assetSetID: String, assetSetVersion: String, clips: [CatAnimationClipID: CatAnimationClip]) {
        guard CatAnimationClipID.allCases.allSatisfy({ clips[$0] != nil }) else { return nil }
        self.assetSetID = assetSetID; self.assetSetVersion = assetSetVersion; self.clips = clips
    }
    subscript(id: CatAnimationClipID) -> CatAnimationClip { clips[id]! }
}
