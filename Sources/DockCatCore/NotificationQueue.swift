import Foundation

public actor NotificationQueue {
    public enum EnqueueResult: Equatable, Sendable { case accepted, duplicate, full }
    public enum ExternalMutationResult: Equatable, Sendable {
        case inserted, updatedCurrent, updatedPending, removedCurrent, removedPending, notFound, duplicate, full
    }
    public enum ExternalLocation: Equatable, Sendable { case current, pending(index: Int) }

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

    public func enqueueAppeared(_ notification: DockCatNotification) -> ExternalMutationResult {
        guard let identity = notification.externalIdentity else { return .notFound }
        guard location(of: identity) == nil else { return .duplicate }
        switch enqueue(notification) { case .accepted: return .inserted; case .duplicate: return .duplicate; case .full: return .full }
    }

    public func updateExternal(_ notification: DockCatNotification) -> ExternalMutationResult {
        guard let identity = notification.externalIdentity else { return .notFound }
        if let old = current, old.externalIdentity == identity { current = notification.preservingIdentity(of: old); return .updatedCurrent }
        guard let index = pending.firstIndex(where: { $0.externalIdentity == identity }) else { return .notFound }
        pending[index] = notification.preservingIdentity(of: pending[index]); return .updatedPending
    }

    public func removeExternal(_ identity: ExternalNotificationIdentity) -> ExternalMutationResult {
        if current?.externalIdentity == identity { current = nil; return .removedCurrent }
        guard let index = pending.firstIndex(where: { $0.externalIdentity == identity }) else { return .notFound }
        pending.remove(at: index); return .removedPending
    }

    public func location(of identity: ExternalNotificationIdentity) -> ExternalLocation? {
        if current?.externalIdentity == identity { return .current }
        return pending.firstIndex(where: { $0.externalIdentity == identity }).map(ExternalLocation.pending)
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

private extension DockCatNotification {
    func preservingIdentity(of old: DockCatNotification) -> DockCatNotification {
        .init(id: old.id, sourceName: sourceName, title: title, message: message, presentation: presentation,
              actionURL: actionURL, createdAt: old.createdAt, externalIdentity: externalIdentity, classification: classification)
    }
}
