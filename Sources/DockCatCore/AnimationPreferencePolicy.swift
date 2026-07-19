import Foundation

public struct AnimationPreferenceInputs: Equatable, Sendable {
    public var appReducedMotion: Bool
    public var systemReducedMotion: Bool
    public var disableWalking: Bool
    public var pauseAnimations: Bool
    public var idleAnimation: Bool
    public var animationSpeed: Double
    public var catScale: Double

    public init(
        appReducedMotion: Bool,
        systemReducedMotion: Bool,
        disableWalking: Bool,
        pauseAnimations: Bool,
        idleAnimation: Bool,
        animationSpeed: Double,
        catScale: Double
    ) {
        self.appReducedMotion = appReducedMotion
        self.systemReducedMotion = systemReducedMotion
        self.disableWalking = disableWalking
        self.pauseAnimations = pauseAnimations
        self.idleAnimation = idleAnimation
        self.animationSpeed = animationSpeed
        self.catScale = catScale
    }
}

public enum VisualAnimationMode: String, Equatable, Sendable {
    case full
    case reducedMotion
    case walkingDisabled
    case animationsPaused
}

public struct EffectiveAnimationPreferences: Equatable, Sendable {
    public static let speedRange = 0.25...4.0
    public static let catScaleRange = 0.5...2.0

    public let mode: VisualAnimationMode
    public let appReducedMotion: Bool
    public let systemReducedMotion: Bool
    public let idleAnimationEnabled: Bool
    public let speed: Double
    public let catScale: Double

    public var isReducedMotionEffective: Bool {
        appReducedMotion || systemReducedMotion
    }

    public init(inputs: AnimationPreferenceInputs) {
        appReducedMotion = inputs.appReducedMotion
        systemReducedMotion = inputs.systemReducedMotion
        idleAnimationEnabled = inputs.idleAnimation
        speed = Self.clampedSpeed(inputs.animationSpeed)
        catScale = Self.clampedCatScale(inputs.catScale)

        // Pausing wins because it promises an immediate deterministic final state.
        // Accessibility Reduced Motion wins over the optional walking preference so every
        // visual surface follows the stronger system/app request. Disable Walking then
        // changes travel only; full animation is the fallback.
        if inputs.pauseAnimations {
            mode = .animationsPaused
        } else if inputs.appReducedMotion || inputs.systemReducedMotion {
            mode = .reducedMotion
        } else if inputs.disableWalking {
            mode = .walkingDisabled
        } else {
            mode = .full
        }
    }

    public static let `default` = EffectiveAnimationPreferences(inputs: .init(
        appReducedMotion: false,
        systemReducedMotion: false,
        disableWalking: false,
        pauseAnimations: false,
        idleAnimation: true,
        animationSpeed: 1,
        catScale: 1
    ))

    public static func clampedSpeed(_ value: Double) -> Double {
        clamp(value, to: speedRange, fallback: 1)
    }

    public static func clampedCatScale(_ value: Double) -> Double {
        clamp(value, to: catScaleRange, fallback: 1)
    }

    private static func clamp(
        _ value: Double,
        to range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
