import Foundation

public struct CatOverlayGeometry: Equatable, Sendable {
    /// Stable artwork measurements relative to the logical Dock anchor at scale 1.
    public static let artworkSize = Size(width: 116, height: 68)
    public static let basePanelSize = Size(width: 150, height: 110)
    public static let baseVisualAnchor = Point(x: 75, y: 35)
    public static let baseCarryOffset = Point(x: 42, y: 38)
    public static let baseHandoffSize = Size(width: 36, height: 24)

    // These named margins protect the vector tail/paws, facing rotation, and breathing.
    public static let tailAndPawPadding = 10.0
    public static let rotationPadding = 5.0
    public static let breathingPadding = 2.0
    public static let minimumSafetyPadding =
        tailAndPawPadding + rotationPadding + breathingPadding

    public let scale: Double
    public let scaledArtworkSize: Size
    public let panelSize: Size
    public let safetyPadding: Double
    public let visualAnchorInPanel: Point
    public let carryOffset: Point
    public let handoffSize: Size

    public init(scale requestedScale: Double) {
        let scale = EffectiveAnimationPreferences.clampedCatScale(requestedScale)
        self.scale = scale
        scaledArtworkSize = Self.artworkSize.scaled(by: scale)
        safetyPadding = Self.minimumSafetyPadding

        // Preserve the established 150x110 and 75x35 contract at scale 1. Changes in
        // artwork extent grow/shrink around the logical visual anchor, while named safety
        // padding remains present at every supported scale.
        let width = max(
            scaledArtworkSize.width + safetyPadding * 2,
            Self.basePanelSize.width + (scale - 1) * Self.artworkSize.width
        )
        let height = max(
            scaledArtworkSize.height + safetyPadding * 2,
            Self.basePanelSize.height + (scale - 1) * Self.artworkSize.height
        )
        panelSize = Size(width: width, height: height)
        visualAnchorInPanel = Point(
            x: Self.baseVisualAnchor.x + (scale - 1) * Self.artworkSize.width / 2,
            y: Self.baseVisualAnchor.y + (scale - 1) * 18
        )
        carryOffset = Self.baseCarryOffset.scaled(by: scale)
        handoffSize = Self.baseHandoffSize.scaled(by: scale)
    }

    public func panelOrigin(preservingGlobalVisualAnchor anchor: Point) -> Point {
        Point(
            x: anchor.x - visualAnchorInPanel.x,
            y: anchor.y - visualAnchorInPanel.y
        )
    }

    public func globalVisualAnchor(forPanelOrigin origin: Point) -> Point {
        Point(
            x: origin.x + visualAnchorInPanel.x,
            y: origin.y + visualAnchorInPanel.y
        )
    }

    public func handoffFrame(
        forGlobalVisualAnchor anchor: Point,
        facing: CatFacing = .right
    ) -> Rect {
        let offset = transformedCarryOffset(for: facing)
        let center = Point(x: anchor.x + offset.x, y: anchor.y + offset.y)
        return Rect(
            x: center.x - handoffSize.width / 2,
            y: center.y - handoffSize.height / 2,
            width: handoffSize.width,
            height: handoffSize.height
        )
    }

    public func presentationExclusionFrame(forGlobalVisualAnchor anchor: Point) -> Rect {
        let origin = panelOrigin(preservingGlobalVisualAnchor: anchor)
        return Rect(
            x: origin.x, y: origin.y,
            width: panelSize.width, height: panelSize.height
        )
    }

    public func transformedCarryOffset(for facing: CatFacing) -> Point {
        switch facing {
        case .left:
            Point(x: -carryOffset.x, y: carryOffset.y)
        case .right, .resting:
            carryOffset
        case .up:
            Point(x: -carryOffset.y, y: carryOffset.x)
        case .down:
            Point(x: carryOffset.y, y: -carryOffset.x)
        }
    }

}

private extension Size {
    func scaled(by scale: Double) -> Size {
        Size(width: width * scale, height: height * scale)
    }
}

private extension Point {
    func scaled(by scale: Double) -> Point {
        Point(x: x * scale, y: y * scale)
    }
}
