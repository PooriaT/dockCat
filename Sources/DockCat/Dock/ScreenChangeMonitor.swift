import AppKit

@MainActor
final class ScreenChangeMonitor {
    private var tokens: [NSObjectProtocol] = []
    init(handler: @escaping @MainActor () -> Void) {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in MainActor.assumeIsolated { handler() } })
        tokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in MainActor.assumeIsolated { handler() } })
    }
    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
    }
}
