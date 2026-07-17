import Foundation

public struct Rect: Equatable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x=x; self.y=y; self.width=width; self.height=height }
    public var minX: Double { x }; public var minY: Double { y }
    public var maxX: Double { x + width }; public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }; public var midY: Double { y + height / 2 }
}

public struct Point: Equatable, Sendable {
    public var x, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Size: Equatable, Sendable {
    public var width, height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public enum DockEdge: String, Equatable, Sendable { case bottom, left, right }
public struct InferredDockGeometry: Equatable, Sendable {
    public let edge: DockEdge; public let thickness: Double
}

public enum DockGeometryInference {
    public static func infer(frame: Rect, visible: Rect, fallbackThickness: Double = 72) -> InferredDockGeometry {
        let left = max(0, visible.x - frame.x), right = max(0, frame.maxX - visible.maxX), bottom = max(0, visible.y - frame.y)
        if left > max(right, bottom), left > 1 { return .init(edge: .left, thickness: left) }
        if right > max(left, bottom), right > 1 { return .init(edge: .right, thickness: right) }
        return .init(edge: .bottom, thickness: bottom > 1 ? bottom : fallbackThickness)
    }
}
