import DockCatCore
import Foundation

@MainActor
protocol CatArtworkRendering: AnyObject {
    func play(clipID: CatAnimationClipID, context: CatAnimationContext?, preferences: EffectiveAnimationPreferences) async -> PresentationAnimationResult
    func showMiniCard()
    func hideMiniCard()
    func resetToSleeping()
    func cancelAnimations()
    func applyVisualPreferences(_ preferences: EffectiveAnimationPreferences)
    var facingForGeometry: CatFacing { get }
}
