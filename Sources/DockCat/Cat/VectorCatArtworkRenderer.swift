import DockCatCore
import Foundation

@MainActor
final class VectorCatArtworkRenderer: CatArtworkRendering {
    private(set) var miniCardVisible = false
    func play(clipID: CatAnimationClipID, context: CatAnimationContext?, preferences: EffectiveAnimationPreferences) async -> PresentationAnimationResult { .completed }
    func showMiniCard() { miniCardVisible = true }
    func hideMiniCard() { miniCardVisible = false }
    func resetToSleeping() { miniCardVisible = false }
    func cancelAnimations() {}
    func applyVisualPreferences(_ preferences: EffectiveAnimationPreferences) {}
    var facingForGeometry: CatFacing { .resting }
}
