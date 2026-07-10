import SwiftUI

@main
struct DockCatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("DockCat.menuBarVisible") private var menuBarVisible = true

    var body: some Scene {
        MenuBarExtra("DockCat", systemImage: "pawprint.fill", isInserted: $menuBarVisible) {
            MenuBarView(state: appDelegate.state)
        }
        .menuBarExtraStyle(.menu)

        Settings { SettingsView(state: appDelegate.state) }
    }
}
