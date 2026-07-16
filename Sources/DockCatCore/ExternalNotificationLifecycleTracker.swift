import Foundation

/// Serialized lifecycle reconciliation. Expiry is driven by one source-level sweep,
/// rather than by creating a task for every observed item.
public actor ExternalNotificationLifecycleTracker {
    public enum ObservationResult: Equatable, Sendable { case event(NotificationSourceEvent), unchanged, unsupportedOrdering }
    private struct Entry: Sendable { var value: ExternalNotification; var lastSeen: Date }
    private var visible: [ExternalNotificationIdentity: Entry] = [:]
    private let capacity: Int
    private let reconciliationTimeout: TimeInterval
    private let now: @Sendable () -> Date

    public init(capacity: Int = 64, reconciliationTimeout: TimeInterval = 12,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.capacity = max(1, capacity); self.reconciliationTimeout = max(0, reconciliationTimeout); self.now = now
    }

    public func observe(_ value: ExternalNotification) -> ObservationResult {
        let timestamp = now()
        if var old = visible[value.identity] {
            old.lastSeen = timestamp
            guard !old.value.notification.semanticallyEquals(value.notification) else { visible[value.identity] = old; return .unchanged }
            old.value = value; visible[value.identity] = old
            return .event(.updated(value))
        }
        guard visible.count < capacity else { return .unsupportedOrdering }
        visible[value.identity] = Entry(value: value, lastSeen: timestamp)
        return .event(.appeared(value))
    }

    public func remove(_ identity: ExternalNotificationIdentity) -> ObservationResult {
        guard visible.removeValue(forKey: identity) != nil else { return .unsupportedOrdering }
        return .event(.disappeared(identity))
    }

    public func reconcile() -> [NotificationSourceEvent] {
        let cutoff = now().addingTimeInterval(-reconciliationTimeout)
        let expired = visible.filter { $0.value.lastSeen <= cutoff }.map(\.key).sorted { $0.stableItemIdentifier < $1.stableItemIdentifier }
        for identity in expired { visible.removeValue(forKey: identity) }
        return expired.map(NotificationSourceEvent.disappeared)
    }

    /// Source stop and permission loss immediately disappear every external item.
    public func sourceStopped() -> [NotificationSourceEvent] {
        let identities = visible.keys.sorted { $0.stableItemIdentifier < $1.stableItemIdentifier }
        visible.removeAll(keepingCapacity: true)
        return identities.map(NotificationSourceEvent.disappeared)
    }

    public func count() -> Int { visible.count }
}


private extension DockCatNotification {
    func semanticallyEquals(_ other: DockCatNotification) -> Bool {
        sourceName == other.sourceName && title == other.title && message == other.message &&
        presentation == other.presentation && actionURL == other.actionURL &&
        externalIdentity == other.externalIdentity && classification == other.classification
    }
}
