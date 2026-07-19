import DockCatCore
import AppKit
import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferences: DockCatPreferences { didSet { save() } }
    @Published private(set) var loginItemError: String?
    private let key = "DockCat.preferences.v1"
    let accessibilityDisplayOptions: AccessibilityDisplayOptionsMonitor

    init(
        accessibilityDisplayOptions: AccessibilityDisplayOptionsMonitor = .init()
    ) {
        self.accessibilityDisplayOptions = accessibilityDisplayOptions
        if let data = UserDefaults.standard.data(forKey: key),
           var value = try? JSONDecoder().decode(DockCatPreferences.self, from: data) {
            value.animationSpeed = EffectiveAnimationPreferences.clampedSpeed(
                value.animationSpeed
            )
            value.catScale = EffectiveAnimationPreferences.clampedCatScale(value.catScale)
            preferences = value
            // Persist a successfully decoded legacy payload through the new encoder.
            save()
        } else {
            preferences = DockCatPreferences()
        }
    }
    var effectiveReducedMotion: Bool {
        preferences.reducedMotion || accessibilityDisplayOptions.reduceMotion
    }
    var effectiveAnimationPreferences: EffectiveAnimationPreferences {
        EffectiveAnimationPreferences(inputs: .init(
            appReducedMotion: preferences.reducedMotion,
            systemReducedMotion: accessibilityDisplayOptions.reduceMotion,
            disableWalking: preferences.disableWalking,
            pauseAnimations: preferences.pauseAnimations,
            idleAnimation: preferences.idleAnimation,
            animationSpeed: preferences.animationSpeed,
            catScale: preferences.catScale
        ))
    }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLaunchAtLogin(_ enabled: Bool) {
        do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); loginItemError = nil }
        catch { loginItemError = error.localizedDescription }
        objectWillChange.send()
    }
    private func save() { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: key) } }
}
