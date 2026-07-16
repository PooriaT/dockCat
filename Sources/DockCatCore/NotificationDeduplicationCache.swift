import Foundation

public actor NotificationDeduplicationCache {
    public enum Result: Sendable, Equatable { case accepted, duplicate, expiredReplacement }
    public struct Observation: Sendable, Equatable {
        public let sequence: UInt64
        public init(sequence: UInt64) { self.sequence = sequence }
    }
    private struct Record: Sendable { let observedAt: Date; let ordinal: UInt64; let observation: Observation }
    private var records: [NotificationFingerprint: Record] = [:]
    private var ordinal: UInt64 = 0
    public let retention: TimeInterval
    public let capacity: Int
    private let now: @Sendable () -> Date

    public init(retention: TimeInterval = 15, capacity: Int = 256, now: @escaping @Sendable () -> Date = Date.init) {
        self.retention = max(0, retention); self.capacity = max(1, capacity); self.now = now
    }
    public func observe(_ fingerprint: NotificationFingerprint, metadata: Observation) -> Result {
        let date = now(); let existedBeforeExpiry = records[fingerprint] != nil; evictExpired(at: date)
        if records[fingerprint] != nil { return .duplicate }
        let result: Result = existedBeforeExpiry ? .expiredReplacement : .accepted
        ordinal &+= 1; records[fingerprint] = .init(observedAt: date, ordinal: ordinal, observation: metadata)
        evictOverCapacity()
        return result
    }
    public func remove(_ fingerprint: NotificationFingerprint) { records.removeValue(forKey: fingerprint) }
    public func count() -> Int { records.count }
    public func contains(_ fingerprint: NotificationFingerprint) -> Bool { records[fingerprint] != nil }
    private func evictExpired(at date: Date) {
        records = records.filter { date.timeIntervalSince($0.value.observedAt) < retention }
    }
    private func evictOverCapacity() {
        while records.count > capacity, let oldest = records.min(by: { ($0.value.observedAt, $0.value.ordinal) < ($1.value.observedAt, $1.value.ordinal) })?.key { records.removeValue(forKey: oldest) }
    }
}
