import Foundation

public actor NotificationQueue {
    public enum EnqueueResult: Equatable, Sendable { case accepted, duplicate, full }

    private var pending: [DockCatNotification] = []
    private var current: DockCatNotification?
    private var knownIDs: Set<UUID> = []
    private var paused = false
    public var limit: Int

    public init(limit: Int = 20) { self.limit = max(1, limit) }

    public func enqueue(_ notification: DockCatNotification) -> EnqueueResult {
        guard !knownIDs.contains(notification.id) else { return .duplicate }
        guard pending.count + (current == nil ? 0 : 1) < limit else { return .full }
        knownIDs.insert(notification.id)
        pending.append(notification)
        return .accepted
    }

    public func next() -> DockCatNotification? {
        guard !paused else { return current }
        if let current { return current }
        guard !pending.isEmpty else { return nil }
        current = pending.removeFirst()
        return current
    }

    @discardableResult public func completeCurrent() -> DockCatNotification? {
        guard let current else { return nil }
        self.current = nil
        return current
    }

    public func setLimit(_ value: Int) { limit = max(1, value) }
    public func setPaused(_ value: Bool) { paused = value }
    public func isPaused() -> Bool { paused }
    public func hasPending() -> Bool { !pending.isEmpty }
    public func count() -> Int { pending.count + (current == nil ? 0 : 1) }
    public func currentNotification() -> DockCatNotification? { current }
}
