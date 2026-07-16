import Foundation

public actor SystemNotificationPipeline {
    public enum Result: Sendable, Equatable { case enqueued, updatedCurrent, updatedPending, removedCurrent, removedPending, rejected(AccessibilityNotificationRejection), duplicate, queueFull, notFound }
    private let parser: AccessibilityNotificationParser
    private let exclusions: AccessibilityNotificationExclusionPolicy
    private let tracker: ExternalNotificationLifecycleTracker
    private let queue: NotificationQueue
    private let policy: ExternalPresentationPolicy

    public init(queue: NotificationQueue, ownBundleIdentifier: String,
                parser: AccessibilityNotificationParser = .init(),
                deduplication: NotificationDeduplicationCache = .init(),
                tracker: ExternalNotificationLifecycleTracker = .init()) {
        self.queue = queue; self.parser = parser; self.exclusions = .init(ownBundleIdentifier: ownBundleIdentifier)
        self.tracker = tracker; self.policy = .init()
        _ = deduplication // retained in the source-compatible initializer; lifecycle identity now owns deduplication.
    }

    public func ingest(_ snapshot: AccessibilityNotificationSnapshot, transientDuration: TimeInterval) async -> Result {
        if snapshot.observationKind == .destroyed {
            guard let identity = identity(for: snapshot) else { return .rejected(.disappeared) }
            guard case .event(let event) = await tracker.remove(identity) else { return .rejected(.disappeared) }
            return await apply(event)
        }
        let candidate: AccessibilityNotificationCandidate
        switch parser.parse(snapshot) { case .failure(let rejection): return .rejected(rejection); case .success(let value): candidate = value }
        if let rejection = exclusions.rejection(for: candidate) { return .rejected(rejection) }
        let identity = identity(for: candidate)
        let classification = policy.classify(candidate)
        let presentation: DockCatNotification.Presentation
        let evidence: DockCatNotification.Classification
        switch classification {
        case .transient(let reason): presentation = .transient(duration: transientDuration); evidence = .confident(reason)
        case .persistent(let reason): presentation = .persistent; evidence = .confident(reason)
        case .ambiguous(let reason): presentation = .persistent; evidence = .bestEffort(reason)
        }
        let item = DockCatNotification(sourceName: candidate.sourceDisplayName.displayValue ?? "System Notification",
            title: candidate.title.displayValue ?? "", message: candidate.message.displayValue ?? "",
            presentation: presentation, externalIdentity: identity, classification: evidence)
        switch await tracker.observe(.init(identity: identity, notification: item)) {
        case .unchanged: return .duplicate
        case .unsupportedOrdering: return .queueFull
        case .event(let event):
            let result = await apply(event)
            if result == .queueFull { _ = await tracker.remove(identity) }
            return result
        }
    }

    public func sourceStopped() async -> [Result] {
        var results: [Result] = []
        for event in await tracker.sourceStopped() { results.append(await apply(event)) }
        return results
    }

    public func reconcile() async -> [Result] {
        var results: [Result] = []
        for event in await tracker.reconcile() { results.append(await apply(event)) }
        return results
    }

    private func apply(_ event: NotificationSourceEvent) async -> Result {
        let outcome: NotificationQueue.ExternalMutationResult
        switch event {
        case .appeared(let value): outcome = await queue.enqueueAppeared(value.notification)
        case .updated(let value): outcome = await queue.updateExternal(value.notification)
        case .disappeared(let identity): outcome = await queue.removeExternal(identity)
        default: return .notFound
        }
        switch outcome {
        case .inserted: return .enqueued; case .updatedCurrent: return .updatedCurrent; case .updatedPending: return .updatedPending
        case .removedCurrent: return .removedCurrent; case .removedPending: return .removedPending; case .duplicate: return .duplicate
        case .full: return .queueFull; case .notFound: return .notFound
        }
    }

    private func identity(for candidate: AccessibilityNotificationCandidate) -> ExternalNotificationIdentity {
        let stable = candidate.capture.stableContainerIdentifier ?? candidate.opaqueDismissalTokenIdentifier ?? candidate.capture.coarseStructuralSignature
        return .init(sourceNamespace: "macos.accessibility.notification-center", stableItemIdentifier: stable)
    }
    private func identity(for snapshot: AccessibilityNotificationSnapshot) -> ExternalNotificationIdentity? {
        guard let stable = snapshot.observedElementIdentifier ?? snapshot.opaqueDismissalTokenIdentifier else { return nil }
        return .init(sourceNamespace: "macos.accessibility.notification-center", stableItemIdentifier: stable)
    }
}
