import Foundation

/// Serialized lifecycle reconciliation for notifications whose disappearance is
/// reported explicitly by their source.
public actor ExternalNotificationLifecycleTracker {
    public enum ObservationResult: Equatable, Sendable { case event(NotificationSourceEvent), unchanged, unsupportedOrdering }
    private var visible: [ExternalNotificationIdentity: ExternalNotification] = [:]
    private let capacity: Int

    public init(capacity: Int = 64, reconciliationTimeout _: TimeInterval = 12,
                now _: @escaping @Sendable () -> Date = Date.init) {
        self.capacity = max(1, capacity)
    }

    public func observe(_ value: ExternalNotification) -> ObservationResult {
        if let old = visible[value.identity] {
            guard !old.notification.semanticallyEquals(value.notification) else { return .unchanged }
            visible[value.identity] = value
            return .event(.updated(value))
        }
        guard visible.count < capacity else { return .unsupportedOrdering }
        visible[value.identity] = value
        return .event(.appeared(value))
    }

    public func remove(_ identity: ExternalNotificationIdentity) -> ObservationResult {
        guard visible.removeValue(forKey: identity) != nil else { return .unsupportedOrdering }
        return .event(.disappeared(identity))
    }

    public func reconcile() -> [NotificationSourceEvent] {
        // Silence is not evidence of disappearance: Accessibility does not emit
        // callbacks for an unchanged banner and this source has no authoritative
        // tree rescan. Items remain visible until a destruction or source-stop event.
        []
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
