import Foundation

public actor SystemNotificationPipeline {
    public enum Result: Sendable, Equatable {
        case enqueued
        case rejected(AccessibilityNotificationRejection)
        case duplicate
        case queueFull
    }
    private let parser: AccessibilityNotificationParser
    private let exclusions: AccessibilityNotificationExclusionPolicy
    private let deduplication: NotificationDeduplicationCache
    private let queue: NotificationQueue

    public init(queue: NotificationQueue, ownBundleIdentifier: String,
                parser: AccessibilityNotificationParser = .init(),
                deduplication: NotificationDeduplicationCache = .init()) {
        self.queue = queue; self.parser = parser
        self.exclusions = .init(ownBundleIdentifier: ownBundleIdentifier)
        self.deduplication = deduplication
    }

    public func ingest(_ snapshot: AccessibilityNotificationSnapshot, transientDuration: TimeInterval) async -> Result {
        let candidate: AccessibilityNotificationCandidate
        switch parser.parse(snapshot) {
        case .failure(let rejection): return .rejected(rejection)
        case .success(let value): candidate = value
        }
        guard candidate.lifecycleHint != .disappeared else { return .rejected(.disappeared) }
        if let rejection = exclusions.rejection(for: candidate) { return .rejected(rejection) }
        let fingerprint = NotificationFingerprint.make(for: candidate)
        let duplicate = await deduplication.observe(fingerprint, metadata: .init(sequence: candidate.capture.sequence))
        guard duplicate != .duplicate else { return .duplicate }
        let notification = DockCatNotification(
            sourceName: candidate.sourceDisplayName.displayValue ?? "System Notification",
            title: candidate.title.displayValue ?? "",
            message: candidate.message.displayValue ?? "",
            presentation: .transient(duration: transientDuration), actionURL: nil,
            externalIdentity: .init(fingerprint: fingerprint.rawValue, sourceBundleIdentifier: candidate.sourceBundleIdentifier)
        )
        switch await queue.enqueue(notification) {
        case .accepted: return .enqueued
        case .duplicate: await deduplication.remove(fingerprint); return .duplicate
        case .full:
            // Failed delivery is not remembered, allowing a later callback to retry.
            await deduplication.remove(fingerprint); return .queueFull
        }
    }
}
