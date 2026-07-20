import XCTest
@testable import DockCat
import DockCatCore

@MainActor final class SettingsUITypeRegressionTests: XCTestCase {
    func testAppStateExposesConcreteSettingsTypesUsedBySettingsUI() {
        assertKeyPath(\AppState.settings, hasType: SettingsStore.self)
        assertKeyPath(\AppState.systemNotificationAccess, hasType: SystemNotificationAccessController.self)
    }

    func testDiagnosticsUseExistingBannerClosePreference() {
        let preferenceKeyPath: WritableKeyPath<DockCatPreferences, Bool> = \DockCatPreferences.closeOriginalBannerAfterCapture
        var preferences = DockCatPreferences()
        preferences[keyPath: preferenceKeyPath] = true
        XCTAssertTrue(preferences.closeOriginalBannerAfterCapture)
    }

    private func assertKeyPath<Root, Value>(_ keyPath: KeyPath<Root, Value>, hasType: Value.Type) {}
}
