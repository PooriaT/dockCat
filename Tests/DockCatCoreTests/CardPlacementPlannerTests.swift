import DockCatCore
import XCTest

final class CardPlacementPlannerTests: XCTestCase {
    private let screen = Rect(x: 0, y: 0, width: 1_000, height: 800)

    func testPreferredPlacementForEveryDockEdge() {
        XCTAssertEqual(
            plan(edge: .bottom, anchor: .init(x: 500, y: 100), cat: .init(x: 480, y: 90, width: 40, height: 40)).frame,
            Rect(x: 330, y: 152, width: 340, height: 150)
        )
        XCTAssertEqual(
            plan(edge: .left, anchor: .init(x: 100, y: 400), cat: .init(x: 90, y: 380, width: 40, height: 40)).frame,
            Rect(x: 152, y: 325, width: 340, height: 150)
        )
        XCTAssertEqual(
            plan(edge: .right, anchor: .init(x: 900, y: 400), cat: .init(x: 860, y: 380, width: 40, height: 40)).frame,
            Rect(x: 498, y: 325, width: 340, height: 150)
        )
    }

    func testPreferredDirectionsAreTyped() {
        XCTAssertEqual(plan(edge: .bottom).preferredDirection, .above)
        XCTAssertEqual(plan(edge: .left).preferredDirection, .right)
        XCTAssertEqual(plan(edge: .right).preferredDirection, .left)
    }

    func testFullFrameClampsAtEveryVisibleScreenEdge() {
        let anchors = [
            Point(x: 0, y: 0), Point(x: 1_000, y: 0),
            Point(x: 0, y: 800), Point(x: 1_000, y: 800),
        ]
        for edge in [DockEdge.bottom, .left, .right] {
            for anchor in anchors {
                let result = plan(edge: edge, anchor: anchor)
                XCTAssertGreaterThanOrEqual(result.frame.minX, 10)
                XCTAssertGreaterThanOrEqual(result.frame.minY, 10)
                XCTAssertLessThanOrEqual(result.frame.maxX, 990)
                XCTAssertLessThanOrEqual(result.frame.maxY, 790)
                XCTAssertTrue(result.wasClamped)
            }
        }
    }

    func testNegativeOriginSecondaryDisplayIsPreserved() {
        let result = plan(
            edge: .bottom,
            anchor: Point(x: -960, y: 100),
            visible: Rect(x: -1_920, y: -120, width: 1_920, height: 1_080)
        )
        XCTAssertEqual(result.frame, Rect(x: -1_130, y: 122, width: 340, height: 150))
        XCTAssertFalse(result.wasClamped)
    }

    func testShortAndTallCardsUseTheirActualHeight() {
        let short = plan(edge: .bottom, size: Size(width: 340, height: 120))
        let tall = plan(edge: .bottom, size: Size(width: 340, height: 420))
        XCTAssertEqual(short.frame.height, 120)
        XCTAssertEqual(tall.frame.height, 420)
        XCTAssertEqual(short.frame.minY, tall.frame.minY)
    }

    func testOversizedCardIsConstrainedToMarginAdjustedVisibleFrame() {
        let result = plan(
            edge: .bottom,
            anchor: Point(x: 100, y: 50),
            size: Size(width: 800, height: 600),
            visible: Rect(x: -200, y: -100, width: 400, height: 300)
        )
        XCTAssertEqual(result.frame.width, 380)
        XCTAssertEqual(result.frame.height, 280)
        XCTAssertEqual(result.frame.minX, -190)
        XCTAssertEqual(result.frame.minY, -90)
        XCTAssertTrue(result.wasClamped)
        XCTAssertTrue(
            result.degradation == .sizeConstrained
                || result.degradation == .sizeConstrainedAndUnavoidableCollision
        )
    }

    func testClampCollisionUsesSecondaryDockAxisAdjustment() {
        let result = plan(
            edge: .bottom,
            anchor: Point(x: 500, y: 760),
            cat: Rect(x: 480, y: 740, width: 40, height: 40)
        )
        XCTAssertEqual(result.frame, Rect(x: 118, y: 640, width: 340, height: 150))
        XCTAssertEqual(472 - result.frame.maxX, 14)
        XCTAssertTrue(result.wasClamped)
        XCTAssertTrue(result.usedCollisionFallback)
        XCTAssertEqual(result.degradation, .none)
    }

    func testOppositeSideCollisionFallbackPreservesConfiguredOffset() {
        let result = plan(
            edge: .bottom,
            anchor: Point(x: 200, y: 760),
            visible: Rect(x: 0, y: 0, width: 400, height: 800),
            cat: Rect(x: 180, y: 740, width: 40, height: 40),
            offset: 37
        )

        XCTAssertEqual(result.frame, Rect(x: 30, y: 545, width: 340, height: 150))
        XCTAssertEqual(732 - result.frame.maxY, 37)
        XCTAssertTrue(result.usedCollisionFallback)
        XCTAssertEqual(result.degradation, .none)
    }

    func testDegradedNoFitResultIsTyped() {
        let result = plan(
            edge: .bottom,
            anchor: Point(x: 100, y: 50),
            size: Size(width: 340, height: 150),
            visible: Rect(x: 0, y: 0, width: 200, height: 100),
            cat: Rect(x: 0, y: 0, width: 200, height: 100)
        )
        XCTAssertEqual(result.frame, Rect(x: 10, y: 10, width: 180, height: 80))
        XCTAssertEqual(result.degradation, .sizeConstrainedAndUnavoidableCollision)
        XCTAssertTrue(result.usedCollisionFallback)
    }

    func testOffsetAndScreenMarginHaveNamedConsistentEffects() {
        let zeroOffset = plan(edge: .left, offset: 0, margin: 20)
        let extraOffset = plan(edge: .left, offset: 37, margin: 20)
        XCTAssertEqual(extraOffset.frame.x - zeroOffset.frame.x, 37)
        XCTAssertGreaterThanOrEqual(extraOffset.frame.minX, 20)
        XCTAssertLessThanOrEqual(extraOffset.frame.maxX, 980)
    }

    func testRepeatedInputsProduceExactSamePlan() {
        let input = CardPlacementInput(
            presentationAnchor: Point(x: -42, y: 777),
            dockEdge: .right,
            cardSize: Size(width: 333, height: 211),
            visibleScreenFrame: Rect(x: -1_200, y: 300, width: 1_200, height: 700),
            catExclusionFrame: Rect(x: -70, y: 750, width: 60, height: 50),
            offset: 23,
            screenMargin: 11
        )
        XCTAssertEqual(CardPlacementPlanner.plan(input), CardPlacementPlanner.plan(input))
    }

    private func plan(
        edge: DockEdge,
        anchor: Point = Point(x: 500, y: 100),
        size: Size = Size(width: 340, height: 150),
        visible: Rect? = nil,
        cat: Rect? = nil,
        offset: Double = 14,
        margin: Double = 10
    ) -> CardPlacementPlan {
        CardPlacementPlanner.plan(
            CardPlacementInput(
                presentationAnchor: anchor,
                dockEdge: edge,
                cardSize: size,
                visibleScreenFrame: visible ?? screen,
                catExclusionFrame: cat,
                offset: offset,
                screenMargin: margin
            )
        )
    }
}
