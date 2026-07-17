import AppKit

struct NotificationCenterProcess: Equatable, Sendable { let bundleIdentifier: String?; let processIdentifier: pid_t; let localizedName: String? }
enum NotificationCenterResolution: Equatable, Sendable { case resolved(NotificationCenterProcess); case unavailable; case degraded(NotificationCenterProcess) }

@MainActor protocol NotificationCenterProcessResolving: AnyObject {
    func resolve() -> NotificationCenterResolution
    func startMonitoring(_ changed: @escaping @MainActor @Sendable () -> Void)
    func stopMonitoring()
}

/// Resolves only the documented compatibility candidates rather than polling every process.
@MainActor final class NotificationCenterProcessResolver: NotificationCenterProcessResolving {
    nonisolated static let bundleIdentifiers = ["com.apple.notificationcenterui", "com.apple.NotificationCenter"]
    nonisolated static let fallbackNames = ["NotificationCenter", "Notification Center"]
    private let workspace: NSWorkspace
    private var tokens: [NSObjectProtocol] = []
    init(workspace: NSWorkspace = .shared) { self.workspace = workspace }
    func resolve() -> NotificationCenterResolution {
        let apps = workspace.runningApplications
        if let app = apps.first(where: { Self.bundleIdentifiers.contains($0.bundleIdentifier ?? "") }) { return .resolved(process(app)) }
        if let app = apps.first(where: { Self.fallbackNames.contains($0.localizedName ?? "") }) { return .degraded(process(app)) }
        return .unavailable
    }
    func startMonitoring(_ changed: @escaping @MainActor @Sendable () -> Void) {
        guard tokens.isEmpty else { return }
        let center = workspace.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      Self.bundleIdentifiers.contains(app.bundleIdentifier ?? "") || Self.fallbackNames.contains(app.localizedName ?? "") else { return }
                MainActor.assumeIsolated { changed() }
            })
        }
    }
    func stopMonitoring() { let center = workspace.notificationCenter; tokens.forEach(center.removeObserver); tokens.removeAll() }
    private func process(_ app: NSRunningApplication) -> NotificationCenterProcess {
        .init(bundleIdentifier: app.bundleIdentifier, processIdentifier: app.processIdentifier, localizedName: app.localizedName)
    }
}
