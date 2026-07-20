import DockCatCore
import Foundation

@MainActor
final class SpriteAtlasCatArtworkRenderer: CatArtworkRendering {
    private let library: CatAnimationClipLibrary
    private(set) var playCounts: [CatAnimationClipID: Int] = [:]
    private(set) var miniCardVisible = false
    init(library: CatAnimationClipLibrary) { self.library = library }
    func play(clipID: CatAnimationClipID, context: CatAnimationContext?, preferences: EffectiveAnimationPreferences) async -> PresentationAnimationResult {
        _ = library[clipID]
        if preferences.mode == .walkingDisabled && (clipID == .walkCarry || clipID == .walkHome) { return .completed }
        if playCounts[clipID] == nil || !(clipID == .walkCarry || clipID == .walkHome || clipID == .sleep || clipID == .wait) { playCounts[clipID, default: 0] += 1 }
        if [.pickUp, .walkCarry, .present, .wait].contains(clipID) { miniCardVisible = true }
        if clipID == .settle || clipID == .sleep { miniCardVisible = false }
        return .completed
    }
    func showMiniCard() { miniCardVisible = true }
    func hideMiniCard() { miniCardVisible = false }
    func resetToSleeping() { miniCardVisible = false }
    func cancelAnimations() {}
    func applyVisualPreferences(_ preferences: EffectiveAnimationPreferences) {}
    var facingForGeometry: CatFacing { .resting }
}
