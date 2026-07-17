import DockCatCore
import AppKit
import Foundation
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    @Published var preferences: DockCatPreferences { didSet { save() } }
    @Published private(set) var loginItemError: String?
    private let key = "DockCat.preferences.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let value = try? JSONDecoder().decode(DockCatPreferences.self, from: data) {
            preferences = value
            // Persist a successfully decoded legacy payload through the new encoder.
            save()
        } else {
            preferences = DockCatPreferences()
        }
    }
    var effectiveReducedMotion: Bool { preferences.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || preferences.disableWalking }
    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLaunchAtLogin(_ enabled: Bool) {
        do { enabled ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister(); loginItemError = nil }
        catch { loginItemError = error.localizedDescription }
        objectWillChange.send()
    }
    private func save() { if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: key) } }
}
