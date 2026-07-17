import Foundation

public enum CardPlacementDirection: String, Equatable, Sendable {
    case above
    case right
    case left
}

public enum CardPlacementDegradation: String, Equatable, Sendable {
    case none
    case sizeConstrained
    case unavoidableCollision
    case sizeConstrainedAndUnavoidableCollision
}

public struct CardPlacementInput: Equatable, Sendable {
    public let presentationAnchor: Point
    public let dockEdge: DockEdge
    public let cardSize: Size
    public let visibleScreenFrame: Rect
    public let catExclusionFrame: Rect?
    public let offset: Double
    public let screenMargin: Double

    public init(
        presentationAnchor: Point,
        dockEdge: DockEdge,
        cardSize: Size,
        visibleScreenFrame: Rect,
        catExclusionFrame: Rect?,
        offset: Double,
        screenMargin: Double
    ) {
        self.presentationAnchor = presentationAnchor
        self.dockEdge = dockEdge
        self.cardSize = cardSize
        self.visibleScreenFrame = visibleScreenFrame
        self.catExclusionFrame = catExclusionFrame
        self.offset = offset
        self.screenMargin = screenMargin
    }
}

public struct CardPlacementPlan: Equatable, Sendable {
    public let frame: Rect
    public let preferredDirection: CardPlacementDirection
    public let wasClamped: Bool
    public let usedCollisionFallback: Bool
    public let degradation: CardPlacementDegradation

    public init(
        frame: Rect,
        preferredDirection: CardPlacementDirection,
        wasClamped: Bool,
        usedCollisionFallback: Bool,
        degradation: CardPlacementDegradation
    ) {
        self.frame = frame
        self.preferredDirection = preferredDirection
        self.wasClamped = wasClamped
        self.usedCollisionFallback = usedCollisionFallback
        self.degradation = degradation
    }
}

public enum CardPlacementPlanner {
    /// Minimum protected distance around both the cat handoff rect and its logical anchor.
    public static let minimumCatGap = 8.0

    public static func plan(_ input: CardPlacementInput) -> CardPlacementPlan {
        let available = availableFrame(
            visibleFrame: input.visibleScreenFrame,
            requestedMargin: input.screenMargin
        )
        let requestedSize = Size(
            width: max(0, input.cardSize.width),
            height: max(0, input.cardSize.height)
        )
        let size = Size(
            width: min(requestedSize.width, available.width),
            height: min(requestedSize.height, available.height)
        )
        let sizeWasConstrained = size != requestedSize
        let protected = protectedFrame(for: input)
        let direction = preferredDirection(for: input.dockEdge)
        let preferred = preferredFrame(
            input: input, size: size, protectedFrame: protected
        )
        let clampedPreferred = clamp(preferred, to: available)
        let wasClamped = sizeWasConstrained || clampedPreferred != preferred

        guard intersects(clampedPreferred, protected) else {
            return CardPlacementPlan(
                frame: clampedPreferred,
                preferredDirection: direction,
                wasClamped: wasClamped,
                usedCollisionFallback: false,
                degradation: sizeWasConstrained ? .sizeConstrained : .none
            )
        }

        let candidates = fallbackCandidates(
            for: input.dockEdge,
            preferred: preferred,
            clampedPreferred: clampedPreferred,
            size: size,
            protectedFrame: protected,
            availableFrame: available
        )
        if let collisionFree = candidates.first(where: { !intersects($0, protected) }) {
            return CardPlacementPlan(
                frame: collisionFree,
                preferredDirection: direction,
                wasClamped: wasClamped,
                usedCollisionFallback: true,
                degradation: sizeWasConstrained ? .sizeConstrained : .none
            )
        }

        return CardPlacementPlan(
            frame: clampedPreferred,
            preferredDirection: direction,
            wasClamped: wasClamped,
            usedCollisionFallback: true,
            degradation: sizeWasConstrained
                ? .sizeConstrainedAndUnavoidableCollision
                : .unavoidableCollision
        )
    }

    private static func preferredDirection(for edge: DockEdge) -> CardPlacementDirection {
        switch edge {
        case .bottom: .above
        case .left: .right
        case .right: .left
        }
    }

    private static func availableFrame(visibleFrame: Rect, requestedMargin: Double) -> Rect {
        let width = max(0, visibleFrame.width)
        let height = max(0, visibleFrame.height)
        let margin = max(0, requestedMargin)
        let horizontalInset = min(margin, width / 2)
        let verticalInset = min(margin, height / 2)
        return Rect(
            x: visibleFrame.x + horizontalInset,
            y: visibleFrame.y + verticalInset,
            width: width - horizontalInset * 2,
            height: height - verticalInset * 2
        )
    }

    private static func protectedFrame(for input: CardPlacementInput) -> Rect {
        let anchor = Rect(
            x: input.presentationAnchor.x,
            y: input.presentationAnchor.y,
            width: 0,
            height: 0
        )
        let combined: Rect
        if let cat = input.catExclusionFrame {
            combined = union(anchor, cat)
        } else {
            combined = anchor
        }
        return inset(combined, by: -minimumCatGap)
    }

    private static func preferredFrame(
        input: CardPlacementInput,
        size: Size,
        protectedFrame: Rect
    ) -> Rect {
        let offset = max(0, input.offset)
        switch input.dockEdge {
        case .bottom:
            return Rect(
                x: input.presentationAnchor.x - size.width / 2,
                y: protectedFrame.maxY + offset,
                width: size.width,
                height: size.height
            )
        case .left:
            return Rect(
                x: protectedFrame.maxX + offset,
                y: input.presentationAnchor.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        case .right:
            return Rect(
                x: protectedFrame.minX - offset - size.width,
                y: input.presentationAnchor.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    /// Returns a strictly bounded, deterministic candidate list. Dock-axis adjustments
    /// are tried first, then the opposite side, then screen corners as a last safe option.
    private static func fallbackCandidates(
        for edge: DockEdge,
        preferred: Rect,
        clampedPreferred: Rect,
        size: Size,
        protectedFrame: Rect,
        availableFrame: Rect
    ) -> [Rect] {
        var raw: [Rect] = []
        switch edge {
        case .bottom:
            raw.append(Rect(x: protectedFrame.minX - size.width, y: clampedPreferred.y, width: size.width, height: size.height))
            raw.append(Rect(x: protectedFrame.maxX, y: clampedPreferred.y, width: size.width, height: size.height))
            raw.append(Rect(x: preferred.x, y: protectedFrame.minY - size.height, width: size.width, height: size.height))
        case .left:
            raw.append(Rect(x: clampedPreferred.x, y: protectedFrame.minY - size.height, width: size.width, height: size.height))
            raw.append(Rect(x: clampedPreferred.x, y: protectedFrame.maxY, width: size.width, height: size.height))
            raw.append(Rect(x: protectedFrame.minX - size.width, y: preferred.y, width: size.width, height: size.height))
        case .right:
            raw.append(Rect(x: clampedPreferred.x, y: protectedFrame.minY - size.height, width: size.width, height: size.height))
            raw.append(Rect(x: clampedPreferred.x, y: protectedFrame.maxY, width: size.width, height: size.height))
            raw.append(Rect(x: protectedFrame.maxX, y: preferred.y, width: size.width, height: size.height))
        }
        raw.append(contentsOf: [
            Rect(x: availableFrame.minX, y: availableFrame.minY, width: size.width, height: size.height),
            Rect(x: availableFrame.minX, y: availableFrame.maxY - size.height, width: size.width, height: size.height),
            Rect(x: availableFrame.maxX - size.width, y: availableFrame.minY, width: size.width, height: size.height),
            Rect(x: availableFrame.maxX - size.width, y: availableFrame.maxY - size.height, width: size.width, height: size.height),
        ])
        return raw.map { clamp($0, to: availableFrame) }
    }

    private static func clamp(_ frame: Rect, to bounds: Rect) -> Rect {
        Rect(
            x: min(max(frame.x, bounds.minX), bounds.maxX - frame.width),
            y: min(max(frame.y, bounds.minY), bounds.maxY - frame.height),
            width: frame.width,
            height: frame.height
        )
    }

    private static func intersects(_ lhs: Rect, _ rhs: Rect) -> Bool {
        lhs.width > 0 && lhs.height > 0
            && lhs.minX < rhs.maxX && lhs.maxX > rhs.minX
            && lhs.minY < rhs.maxY && lhs.maxY > rhs.minY
    }

    private static func inset(_ rect: Rect, by amount: Double) -> Rect {
        Rect(
            x: rect.x + amount,
            y: rect.y + amount,
            width: max(0, rect.width - amount * 2),
            height: max(0, rect.height - amount * 2)
        )
    }

    private static func union(_ lhs: Rect, _ rhs: Rect) -> Rect {
        let minX = min(lhs.minX, rhs.minX)
        let minY = min(lhs.minY, rhs.minY)
        let maxX = max(lhs.maxX, rhs.maxX)
        let maxY = max(lhs.maxY, rhs.maxY)
        return Rect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
