import Testing
@testable import DockCatCore

@Suite("Cat motion planning")
struct CatMotionPlanTests {
    @Test func bottomDockPreservesYAndChangesX() {
        let plan = CatMotionPlanner.plan(from: CatMotionPoint(x: 10, y: 20), requestedDestination: CatMotionPoint(x: 80, y: 200), dockEdge: .bottom, speed: 1, reducedMotion: false)
        #expect(plan.axis == .horizontal)
        #expect(plan.destination == CatMotionPoint(x: 80, y: 20))
        #expect(plan.distance == 70)
    }

    @Test func leftDockPreservesXAndChangesY() {
        let plan = CatMotionPlanner.plan(from: CatMotionPoint(x: 10, y: 20), requestedDestination: CatMotionPoint(x: 80, y: 200), dockEdge: .left, speed: 1, reducedMotion: false)
        #expect(plan.axis == .vertical)
        #expect(plan.destination == CatMotionPoint(x: 10, y: 200))
        #expect(plan.distance == 180)
    }

    @Test func rightDockPreservesXAndChangesY() {
        let plan = CatMotionPlanner.plan(from: CatMotionPoint(x: 10, y: 20), requestedDestination: CatMotionPoint(x: 80, y: -10), dockEdge: .right, speed: 1, reducedMotion: false)
        #expect(plan.axis == .vertical)
        #expect(plan.destination == CatMotionPoint(x: 10, y: -10))
        #expect(plan.distance == 30)
    }

    @Test func progressZeroAndOneReturnEndpoints() {
        let plan = CatMotionPlanner.plan(from: CatMotionPoint(x: 10, y: 20), requestedDestination: CatMotionPoint(x: 110, y: 20), dockEdge: .bottom, speed: 1, reducedMotion: false)
        #expect(plan.point(at: 0) == plan.start)
        #expect(plan.point(at: 1) == plan.destination)
    }

    @Test func progressIsClamped() {
        let plan = CatMotionPlanner.plan(from: CatMotionPoint(x: 10, y: 20), requestedDestination: CatMotionPoint(x: 110, y: 20), dockEdge: .bottom, speed: 1, reducedMotion: false)
        #expect(plan.point(at: -1) == plan.start)
        #expect(plan.point(at: 2) == plan.destination)
    }

    @Test func longerDistanceProducesLongerDuration() {
        let short = CatMotionPlanner.plan(from: CatMotionPoint(x: 0, y: 0), requestedDestination: CatMotionPoint(x: 100, y: 0), dockEdge: .bottom, speed: 1, reducedMotion: false)
        let long = CatMotionPlanner.plan(from: CatMotionPoint(x: 0, y: 0), requestedDestination: CatMotionPoint(x: 400, y: 0), dockEdge: .bottom, speed: 1, reducedMotion: false)
        #expect(long.duration > short.duration)
    }

    @Test func higherSpeedProducesShorterDuration() {
        let slow = CatMotionPlanner.plan(from: CatMotionPoint(x: 0, y: 0), requestedDestination: CatMotionPoint(x: 400, y: 0), dockEdge: .bottom, speed: 0.5, reducedMotion: false)
        let fast = CatMotionPlanner.plan(from: CatMotionPoint(x: 0, y: 0), requestedDestination: CatMotionPoint(x: 400, y: 0), dockEdge: .bottom, speed: 2, reducedMotion: false)
        #expect(fast.duration < slow.duration)
    }

    @Test func speedAndDurationBoundsAreEnforced() {
        let timing = CatMotionTiming(pointsPerSecond: 100, minimumSpeed: 0.5, maximumSpeed: 2, minimumDuration: 0.2, maximumDuration: 1, reducedMotionDuration: 0.1)
        let tiny = CatMotionPlanner.plan(from: CatMotionPoint(x: 0, y: 0), requestedDestination: CatMotionPoint(x: 1, y: 0), dockEdge: .bottom, speed: 100, reducedMotion: false, timing: timing)
        let huge = CatMotionPlanner.plan(from: CatMotionPoint(x: 0, y: 0), requestedDestination: CatMotionPoint(x: 10_000, y: 0), dockEdge: .bottom, speed: 0.01, reducedMotion: false, timing: timing)
        #expect(tiny.duration == 0.2)
        #expect(huge.duration == 1)
        #expect(timing.clampedSpeed(.infinity) == 1)
        #expect(timing.clampedSpeed(100) == 2)
        #expect(timing.clampedSpeed(0.01) == 0.5)
    }

    @Test func reducedMotionProducesShortPlan() {
        let timing = CatMotionTiming(reducedMotionDuration: 0.07)
        let plan = CatMotionPlanner.plan(from: CatMotionPoint(x: 0, y: 0), requestedDestination: CatMotionPoint(x: 10_000, y: 0), dockEdge: .bottom, speed: 0.01, reducedMotion: true, timing: timing)
        #expect(plan.usesReducedMotion)
        #expect(plan.duration == 0.07)
    }

    @Test func cancellationPreventsObsoleteSuccess() {
        var coordinator = CatMotionSessionCoordinator()
        let old = coordinator.startReplacementSession()
        coordinator.cancelActiveSession()
        #expect(coordinator.complete(sessionID: old) == .cancelled)
    }

    @Test func replacementPreventsOldSessionUpdates() {
        var coordinator = CatMotionSessionCoordinator()
        let old = coordinator.startReplacementSession()
        let new = coordinator.startReplacementSession()
        #expect(!coordinator.canUpdate(sessionID: old))
        #expect(coordinator.canUpdate(sessionID: new))
        #expect(coordinator.complete(sessionID: old) == .cancelled)
    }
}
