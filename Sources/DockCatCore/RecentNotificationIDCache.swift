import Foundation

/// FIFO retention for completed notification identities. It stores UUIDs only.
public struct RecentNotificationIDCache: Sendable {
    public let capacity: Int
    private var orderedIDs: [UUID] = []
    private var ids: Set<UUID> = []

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
    }

    public var count: Int { ids.count }

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    public mutating func insert(_ id: UUID) {
        guard capacity > 0, ids.insert(id).inserted else { return }
        orderedIDs.append(id)
        while orderedIDs.count > capacity {
            ids.remove(orderedIDs.removeFirst())
        }
    }
}
