import XCTest
@testable import DockCatCore

final class CardContentLayoutPlannerTests: XCTestCase {
    func testSourceAndShortTitleUseCompactNaturalHeight() {
        let plan = CardContentLayoutPlanner.plan(.init(
            availableWidth: 340,
            availableHeight: 900,
            measurements: .init(
                headerHeight: 16,
                titleHeight: 20,
                bodyHeight: 0,
                actionsHeight: 0,
                queueFooterHeight: 0
            )
        ))

        XCTAssertEqual(plan.cardSize, Size(width: 340, height: 84))
        XCTAssertLessThan(plan.cardSize.height, 120)
        XCTAssertFalse(plan.bodyScrolls)
        XCTAssertEqual(plan.bodyViewportHeight, 0)
    }

    func testShortMessageUsesNaturalViewportWithoutScrolling() {
        let plan = makePlan(body: 38)

        XCTAssertEqual(plan.bodyViewportHeight, 38)
        XCTAssertFalse(plan.bodyScrolls)
        XCTAssertLessThan(plan.cardSize.height, 180)
    }

    func testLongMessageScrollsWithinMaximumWhileControlsRemainAllocated() {
        let plan = makePlan(body: 900, actions: 24, footer: 15)

        XCTAssertEqual(plan.cardSize.height, 480)
        XCTAssertTrue(plan.bodyScrolls)
        XCTAssertEqual(plan.bodyViewportHeight, 321)
        XCTAssertGreaterThan(plan.bodyViewportHeight, 0)
        XCTAssertEqual(plan.titleLineLimit, 3)
    }

    func testActionsAndQueueFooterReduceOnlyBodyAllocation() {
        let plain = makePlan(body: 900)
        let fixedRegions = makePlan(body: 900, actions: 24, footer: 15)

        XCTAssertEqual(plain.cardSize.height, fixedRegions.cardSize.height)
        XCTAssertEqual(
            plain.bodyViewportHeight - fixedRegions.bodyViewportHeight,
            24 + 15 + 14,
            accuracy: 0.001
        )
    }

    func testAvailableScreenHeightFurtherConstrainsMaximum() {
        let plan = makePlan(body: 900, availableHeight: 260)

        XCTAssertEqual(plan.cardSize.height, 260)
        XCTAssertTrue(plan.bodyScrolls)
    }

    func testNarrowAndUnavailableScreensAreSafeAndTyped() {
        let narrow = makePlan(body: 20, availableWidth: 180)
        XCTAssertEqual(narrow.cardSize.width, 180)
        XCTAssertEqual(narrow.degradation, .widthConstrained)

        let unavailable = makePlan(
            body: 100, availableWidth: -20, availableHeight: 0
        )
        XCTAssertEqual(unavailable.cardSize, Size(width: 0, height: 0))
        XCTAssertEqual(unavailable.bodyViewportHeight, 0)
        XCTAssertEqual(unavailable.degradation, .unavailableSpace)
    }

    func testAccessibilityScaleGrowsThenScrollsAtMaximum() {
        let normal = makePlan(body: 200, textScale: 1)
        let large = makePlan(body: 200, textScale: 2.5)

        XCTAssertGreaterThan(large.cardSize.height, normal.cardSize.height)
        XCTAssertTrue(large.bodyScrolls)
        XCTAssertLessThanOrEqual(large.cardSize.height, 480)
    }

    func testNonBodyRegionsHaveTypedSmallScreenDegradation() {
        let plan = makePlan(
            body: 20, actions: 80, footer: 50, availableHeight: 120
        )

        XCTAssertEqual(plan.cardSize.height, 120)
        XCTAssertEqual(plan.bodyViewportHeight, 0)
        XCTAssertEqual(plan.degradation, .nonBodyRegionsConstrained)
    }

    func testPersistentAndTransientContentShareTheSameLayoutInputs() {
        let transient = makeContent(presentation: .transient)
        let persistent = makeContent(presentation: .persistent)

        XCTAssertNotEqual(transient.presentation, persistent.presentation)
        XCTAssertEqual(makePlan(body: 80), makePlan(body: 80))
    }

    func testRepeatedInputsAreExactlyDeterministic() {
        let input = CardContentLayoutInput(
            availableWidth: 340,
            availableHeight: 480,
            measurements: measurements(body: 723, actions: 24, footer: 15)
        )

        XCTAssertEqual(
            CardContentLayoutPlanner.plan(input),
            CardContentLayoutPlanner.plan(input)
        )
    }

    private func makePlan(
        body: Double,
        actions: Double = 0,
        footer: Double = 0,
        availableWidth: Double = 340,
        availableHeight: Double = 900,
        textScale: Double = 1
    ) -> CardContentLayoutPlan {
        CardContentLayoutPlanner.plan(.init(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            measurements: measurements(
                body: body, actions: actions, footer: footer
            ),
            measuredTextScale: textScale
        ))
    }

    private func measurements(
        body: Double,
        actions: Double,
        footer: Double
    ) -> CardContentRegionMeasurements {
        .init(
            headerHeight: 18,
            titleHeight: 40,
            bodyHeight: body,
            actionsHeight: actions,
            queueFooterHeight: footer
        )
    }

    private func makeContent(
        presentation: CardPresentationKind
    ) -> NotificationCardContent {
        .init(
            notificationID: UUID(),
            sourceName: "Example",
            title: "Title",
            message: "Message",
            presentation: presentation,
            hasOpenAction: false,
            canDismiss: true,
            queueContext: .empty
        )
    }
}
