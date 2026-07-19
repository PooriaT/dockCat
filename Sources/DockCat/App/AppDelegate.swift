import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    private var terminationTask: Task<Void, Never>?

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task { @MainActor [state] in
            await state.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
