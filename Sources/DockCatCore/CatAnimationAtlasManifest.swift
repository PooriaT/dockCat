import Foundation

public enum CatAnimationClipID: String, Codable, CaseIterable, Sendable {
    case sleep, wake, pickUp, turnToPresentation, walkCarry, present, wait, turnHome, walkHome, settle
}

public enum CatClipPlayback: String, Codable, Equatable, Sendable { case once, loop, holdLastFrame }
public enum CatClipRestorePolicy: String, Codable, Equatable, Sendable { case preserveFinalFrame, returnToFirstFrame, restoreSleepingClip }
public enum CatAtlasOrientationPolicy: String, Codable, Equatable, Sendable { case canonicalRightFacingMirrorLeftRotateVertical }

public struct CatAtlasAnchorManifest: Codable, Equatable, Sendable {
    public let visualAnchor: Point
    public let feetAnchor: Point
    public let carryAnchor: Point
    public let handoffSize: Size
    public let artworkBounds: Rect?
    public init(visualAnchor: Point, feetAnchor: Point, carryAnchor: Point, handoffSize: Size, artworkBounds: Rect? = nil) {
        self.visualAnchor = visualAnchor; self.feetAnchor = feetAnchor; self.carryAnchor = carryAnchor; self.handoffSize = handoffSize; self.artworkBounds = artworkBounds
    }
}

public struct CatAnimationAtlasManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let assetSetID: String
    public let assetSetVersion: String
    public let atlasName: String
    public let logicalCanvasSize: Size
    public let nativeScale: Int
    public let anchors: CatAtlasAnchorManifest
    public let orientationPolicy: CatAtlasOrientationPolicy
    public let clips: [CatAnimationClipManifest]
    public init(schemaVersion: Int, assetSetID: String, assetSetVersion: String, atlasName: String, logicalCanvasSize: Size, nativeScale: Int, anchors: CatAtlasAnchorManifest, orientationPolicy: CatAtlasOrientationPolicy, clips: [CatAnimationClipManifest]) {
        self.schemaVersion = schemaVersion; self.assetSetID = assetSetID; self.assetSetVersion = assetSetVersion; self.atlasName = atlasName; self.logicalCanvasSize = logicalCanvasSize; self.nativeScale = nativeScale; self.anchors = anchors; self.orientationPolicy = orientationPolicy; self.clips = clips
    }
}

public struct CatAnimationClipManifest: Codable, Equatable, Sendable {
    public let id: CatAnimationClipID
    public let frameNames: [String]
    public let secondsPerFrame: Double
    public let playback: CatClipPlayback
    public let restorePolicy: CatClipRestorePolicy
    public init(id: CatAnimationClipID, frameNames: [String], secondsPerFrame: Double, playback: CatClipPlayback, restorePolicy: CatClipRestorePolicy) {
        self.id = id; self.frameNames = frameNames; self.secondsPerFrame = secondsPerFrame; self.playback = playback; self.restorePolicy = restorePolicy
    }
}
