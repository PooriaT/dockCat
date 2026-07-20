import DockCatCore

/// Holds submissions that arrive after launch begins but before the runtime queue is active.
struct StartupNotificationBuffer {
    private var notifications: [DockCatNotification] = []

    var count: Int { notifications.count }

    mutating func deferIfEnabling(
        _ notification: DockCatNotification,
        runtimeMode: DockCatRuntimeMode
    ) -> Bool {
        guard runtimeMode == .enabling else { return false }
        notifications.append(notification)
        return true
    }

    mutating func drainIfRunning(
        runtimeMode: DockCatRuntimeMode
    ) -> [DockCatNotification] {
        guard runtimeMode.acceptsSubmissions else { return [] }
        let drained = notifications
        notifications.removeAll(keepingCapacity: true)
        return drained
    }

    mutating func removeAll() {
        notifications.removeAll(keepingCapacity: true)
    }
}
