import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { state.receive(url: $0) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state.systemNotificationAccess.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) { state.stop() }
}
