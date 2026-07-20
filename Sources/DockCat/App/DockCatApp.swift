import SwiftUI

@main
struct DockCatApp: App {
    // AppDelegate forwards MenuBarVisibilityController.objectWillChange. Because the delegate
    // is ObservableObject, this adaptor invalidates the scene for URL/Settings-driven changes.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(
            "DockCat",
            systemImage: "pawprint.fill",
            isInserted: Binding(
                get: { appDelegate.menuBarVisibility.isVisible },
                set: { appDelegate.menuBarVisibility.requestVisibility($0) }
            )
        ) {
            MenuBarView(
                state: appDelegate.state,
                settingsPresenter: appDelegate.settingsPresenter
            )
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                state: appDelegate.state,
                menuBarVisibility: appDelegate.menuBarVisibility,
                settingsPresenter: appDelegate.settingsPresenter
            )
        }
    }
}
