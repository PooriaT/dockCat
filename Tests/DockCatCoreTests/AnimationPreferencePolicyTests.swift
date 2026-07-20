import XCTest
@testable import DockCatCore

final class AnimationPreferencePolicyTests: XCTestCase {
    func testModePrecedenceAndIndependentIdlePreference() {
        XCTAssertEqual(policy().mode, .full)
        XCTAssertEqual(policy(appReducedMotion: true).mode, .reducedMotion)
        XCTAssertEqual(policy(systemReducedMotion: true).mode, .reducedMotion)

        let walkingDisabled = policy(disableWalking: true, idleAnimation: false)
        XCTAssertEqual(walkingDisabled.mode, .walkingDisabled)
        XCTAssertFalse(walkingDisabled.isReducedMotionEffective)
        XCTAssertFalse(walkingDisabled.idleAnimationEnabled)

        XCTAssertEqual(
            policy(
                appReducedMotion: true, systemReducedMotion: true,
                disableWalking: true, pauseAnimations: true
            ).mode,
            .animationsPaused
        )
    }

    func testSpeedAndScaleAreClampedAndNonFiniteValuesUseDefaults() {
        XCTAssertEqual(policy(speed: -10, scale: 100).speed, 0.25)
        XCTAssertEqual(policy(speed: -10, scale: 100).catScale, 2)
        XCTAssertEqual(policy(speed: .infinity, scale: .nan).speed, 1)
        XCTAssertEqual(policy(speed: .infinity, scale: .nan).catScale, 1)
    }

    private func policy(
        appReducedMotion: Bool = false,
        systemReducedMotion: Bool = false,
        disableWalking: Bool = false,
        pauseAnimations: Bool = false,
        idleAnimation: Bool = true,
        speed: Double = 1,
        scale: Double = 1
    ) -> EffectiveAnimationPreferences {
        EffectiveAnimationPreferences(inputs: .init(
            appReducedMotion: appReducedMotion,
            systemReducedMotion: systemReducedMotion,
            disableWalking: disableWalking,
            pauseAnimations: pauseAnimations,
            idleAnimation: idleAnimation,
            animationSpeed: speed,
            catScale: scale
        ))
    }
}
