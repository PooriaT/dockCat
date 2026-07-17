import Foundation

public struct Rect: Codable, Equatable, Sendable {
    public var x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x=x; self.y=y; self.width=width; self.height=height }
    public var minX: Double { x }; public var minY: Double { y }
    public var maxX: Double { x + width }; public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }; public var midY: Double { y + height / 2 }
}

public struct Point: Codable, Equatable, Sendable {
    public var x, y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Size: Codable, Equatable, Sendable {
    public var width, height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public enum DockEdge: String, Codable, Equatable, Sendable, CaseIterable { case bottom, left, right }
public enum DockGeometryConfidence: String, Codable, Equatable, Sendable {
    case observedVisibleFrameInset
    case autoHideFallbackEstimate
    case ambiguousEstimate
}
public struct InferredDockGeometry: Equatable, Sendable {
    public let edge: DockEdge
    public let thickness: Double
    public let confidence: DockGeometryConfidence

    public init(
        edge: DockEdge,
        thickness: Double,
        confidence: DockGeometryConfidence = .observedVisibleFrameInset
    ) {
        self.edge = edge
        self.thickness = thickness
        self.confidence = confidence
    }
}

public enum DockGeometryInference {
    public static func infer(frame: Rect, visible: Rect, fallbackThickness: Double = 72) -> InferredDockGeometry {
        let left = max(0, visible.x - frame.x), right = max(0, frame.maxX - visible.maxX), bottom = max(0, visible.y - frame.y)
        let positiveInsets = [left, right, bottom].filter { $0 > 1 }
        let ambiguous = positiveInsets.count > 1 && positiveInsets.sorted(by: >)[0] - positiveInsets.sorted(by: >)[1] < 2
        if left > max(right, bottom), left > 1 {
            return .init(edge: .left, thickness: left, confidence: ambiguous ? .ambiguousEstimate : .observedVisibleFrameInset)
        }
        if right > max(left, bottom), right > 1 {
            return .init(edge: .right, thickness: right, confidence: ambiguous ? .ambiguousEstimate : .observedVisibleFrameInset)
        }
        if bottom > 1 {
            return .init(edge: .bottom, thickness: bottom, confidence: ambiguous ? .ambiguousEstimate : .observedVisibleFrameInset)
        }
        return .init(edge: .bottom, thickness: max(1, fallbackThickness), confidence: .autoHideFallbackEstimate)
    }
}
