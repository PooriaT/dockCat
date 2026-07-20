import Foundation

private func finiteCardMetric(_ value: Double) -> Double {
    value.isFinite ? max(0, value) : 0
}

/// The single metric set shared by the pure planner and the AppKit/SwiftUI boundary.
/// Available dimensions passed to the planner are already inset by `screenMargin`.
public struct CardContentLayoutMetrics: Equatable, Sendable {
    public static let standard = CardContentLayoutMetrics()

    public let preferredWidth: Double
    public let minimumUsableWidth: Double
    public let compactMinimumHeight: Double
    public let maximumHeight: Double
    public let screenMargin: Double
    public let horizontalPadding: Double
    public let verticalPadding: Double
    public let interSectionSpacing: Double
    public let minimumBodyViewportHeight: Double
    public let maximumTitleLines: Int
    public let queueFooterSpacing: Double

    public init(
        preferredWidth: Double = 340,
        minimumUsableWidth: Double = 220,
        compactMinimumHeight: Double = 84,
        maximumHeight: Double = 480,
        screenMargin: Double = 10,
        horizontalPadding: Double = 16,
        verticalPadding: Double = 16,
        interSectionSpacing: Double = 8,
        minimumBodyViewportHeight: Double = 44,
        maximumTitleLines: Int = 3,
        queueFooterSpacing: Double = 6
    ) {
        self.preferredWidth = finiteCardMetric(preferredWidth)
        self.minimumUsableWidth = finiteCardMetric(minimumUsableWidth)
        self.compactMinimumHeight = finiteCardMetric(compactMinimumHeight)
        self.maximumHeight = finiteCardMetric(maximumHeight)
        self.screenMargin = finiteCardMetric(screenMargin)
        self.horizontalPadding = finiteCardMetric(horizontalPadding)
        self.verticalPadding = finiteCardMetric(verticalPadding)
        self.interSectionSpacing = finiteCardMetric(interSectionSpacing)
        self.minimumBodyViewportHeight = finiteCardMetric(minimumBodyViewportHeight)
        self.maximumTitleLines = max(1, maximumTitleLines)
        self.queueFooterSpacing = finiteCardMetric(queueFooterSpacing)
    }
}

public struct CardContentRegionMeasurements: Equatable, Sendable {
    public let headerHeight: Double
    public let titleHeight: Double
    public let bodyHeight: Double
    public let actionsHeight: Double
    public let queueFooterHeight: Double

    public init(
        headerHeight: Double,
        titleHeight: Double,
        bodyHeight: Double,
        actionsHeight: Double,
        queueFooterHeight: Double
    ) {
        self.headerHeight = finiteCardMetric(headerHeight)
        self.titleHeight = finiteCardMetric(titleHeight)
        self.bodyHeight = finiteCardMetric(bodyHeight)
        self.actionsHeight = finiteCardMetric(actionsHeight)
        self.queueFooterHeight = finiteCardMetric(queueFooterHeight)
    }
}

public struct CardContentLayoutInput: Equatable, Sendable {
    public let availableWidth: Double
    public let availableHeight: Double
    public let measurements: CardContentRegionMeasurements
    public let metrics: CardContentLayoutMetrics
    public let measuredTextScale: Double

    public init(
        availableWidth: Double,
        availableHeight: Double,
        measurements: CardContentRegionMeasurements,
        metrics: CardContentLayoutMetrics = .standard,
        measuredTextScale: Double = 1
    ) {
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.measurements = measurements
        self.metrics = metrics
        self.measuredTextScale = measuredTextScale
    }
}

public enum CardContentLayoutDegradation: String, Equatable, Sendable {
    case none
    case widthConstrained
    case bodyViewportReduced
    case nonBodyRegionsConstrained
    case unavailableSpace
}

public struct CardContentLayoutPlan: Equatable, Sendable {
    public let cardSize: Size
    public let bodyViewportHeight: Double
    public let bodyScrolls: Bool
    public let titleLineLimit: Int?
    public let degradation: CardContentLayoutDegradation

    public init(
        cardSize: Size,
        bodyViewportHeight: Double,
        bodyScrolls: Bool,
        titleLineLimit: Int?,
        degradation: CardContentLayoutDegradation
    ) {
        self.cardSize = cardSize
        self.bodyViewportHeight = bodyViewportHeight
        self.bodyScrolls = bodyScrolls
        self.titleLineLimit = titleLineLimit
        self.degradation = degradation
    }
}

public enum CardContentLayoutPlanner {
    public static func plan(_ input: CardContentLayoutInput) -> CardContentLayoutPlan {
        let availableWidth = finiteNonnegative(input.availableWidth)
        let availableHeight = finiteNonnegative(input.availableHeight)
        let metrics = input.metrics
        guard availableWidth > 0, availableHeight > 0,
              metrics.maximumHeight > 0 else {
            return .init(
                cardSize: .init(width: availableWidth, height: 0),
                bodyViewportHeight: 0,
                bodyScrolls: input.measurements.bodyHeight > 0,
                titleLineLimit: metrics.maximumTitleLines,
                degradation: .unavailableSpace
            )
        }

        let width = min(metrics.preferredWidth, availableWidth)
        let maximumHeight = min(metrics.maximumHeight, availableHeight)
        let scale = max(0.5, min(finiteNonnegative(input.measuredTextScale), 4))
        let measured = input.measurements
        let header = measured.headerHeight * scale
        let title = measured.titleHeight * scale
        let body = measured.bodyHeight * scale
        let actions = measured.actionsHeight * scale
        let footer = measured.queueFooterHeight * scale

        let sectionHeights = [header, title, body, actions, footer]
        let populatedCount = sectionHeights.filter { $0 > 0.01 }.count
        let regularGaps = max(0, populatedCount - 1)
        var spacing = Double(regularGaps) * metrics.interSectionSpacing
        if footer > 0, populatedCount > 1 {
            spacing += metrics.queueFooterSpacing - metrics.interSectionSpacing
        }
        spacing = max(0, spacing)

        let nonBodyHeight = metrics.verticalPadding * 2
            + header + title + actions + footer + spacing
        let bodyCapacity = max(0, maximumHeight - nonBodyHeight)
        let bodyViewport = min(body, bodyCapacity)
        let bodyScrolls = body > bodyViewport + 0.5
        let naturalHeight = nonBodyHeight + bodyViewport
        let height = min(maximumHeight, max(metrics.compactMinimumHeight, naturalHeight))

        let degradation: CardContentLayoutDegradation
        if width <= 0 || maximumHeight <= 0 {
            degradation = .unavailableSpace
        } else if nonBodyHeight > maximumHeight + 0.5 {
            degradation = .nonBodyRegionsConstrained
        } else if body > 0, bodyViewport < min(body, metrics.minimumBodyViewportHeight) - 0.5 {
            degradation = .bodyViewportReduced
        } else if width < metrics.minimumUsableWidth {
            degradation = .widthConstrained
        } else {
            degradation = .none
        }

        return .init(
            cardSize: .init(width: width, height: max(0, height)),
            bodyViewportHeight: max(0, bodyViewport),
            bodyScrolls: bodyScrolls,
            titleLineLimit: metrics.maximumTitleLines,
            degradation: degradation
        )
    }

    private static func finiteNonnegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}
