import XCTest
@testable import DockCatCore

final class CatLocomotionTests: XCTestCase {
    func testBottomDockRightAndLeftResolveHorizontalFacing() {
        XCTAssertEqual(context(.bottom, start: .init(x: 0, y: 0), end: .init(x: 50, y: 0)).direction, .right)
        XCTAssertEqual(context(.bottom, start: .init(x: 0, y: 0), end: .init(x: 50, y: 0)).facing, .right)
        XCTAssertEqual(context(.bottom, start: .init(x: 50, y: 0), end: .init(x: 0, y: 0)).direction, .left)
        XCTAssertEqual(context(.bottom, start: .init(x: 50, y: 0), end: .init(x: 0, y: 0)).facing, .left)
    }

    func testVerticalDockPathsResolveVerticalFacing() {
        for edge in [DockEdge.left, .right] {
            XCTAssertEqual(context(edge, start: .init(x: 0, y: 0), end: .init(x: 0, y: 50)).facing, .up)
            XCTAssertEqual(context(edge, start: .init(x: 0, y: 50), end: .init(x: 0, y: 0)).facing, .down)
        }
    }

    func testHomeTravelUsesReverseDirection() {
        let outbound = context(.bottom, start: .init(x: 0, y: 0), end: .init(x: 50, y: 0))
        let home = CatLocomotionResolver.homeContext(from: outbound, phase: .walking)
        XCTAssertEqual(home.direction, .left)
        XCTAssertEqual(home.purpose, .home)
    }

    func testNearZeroMovementIsStationaryStableFacing() {
        let resolved = context(.bottom, start: .init(x: 10, y: 10), end: .init(x: 10.1, y: 10.1))
        XCTAssertEqual(resolved.direction, .stationary)
        XCTAssertEqual(resolved.facing, .right)
    }

    func testMiniCardVisibilityByPhase() {
        for phase in [CatLocomotionPhase.pickingUp, .walking, .staticCarry, .stopping, .waiting, .cancelled] {
            XCTAssertTrue(phase.showsMiniCard)
        }
        for phase in [CatLocomotionPhase.sleeping, .settled, .settling, .turning, .waking] {
            XCTAssertFalse(phase.showsMiniCard)
        }
    }

    func testCancellationAndReducedMotionSelection() {
        XCTAssertEqual(CatLocomotionResolver.phase(after: .cancelled), .cancelled)
        XCTAssertFalse(CatLocomotionResolver.phase(after: .cancelled).isWalkingLoop)
        let reduced = CatLocomotionResolver.travelContext(from: .init(x: 0, y: 0), to: .init(x: 10, y: 0), dockEdge: .bottom, purpose: .presentation, phase: .walking, reducedMotion: true)
        XCTAssertEqual(reduced.phase, .staticCarry)
        XCTAssertFalse(reduced.phase.isWalkingLoop)
    }

    private func context(_ edge: DockEdge, start: CatMotionPoint, end: CatMotionPoint) -> CatAnimationContext {
        CatLocomotionResolver.travelContext(from: start, to: end, dockEdge: edge, purpose: .presentation, phase: .walking, reducedMotion: false)
    }
}
