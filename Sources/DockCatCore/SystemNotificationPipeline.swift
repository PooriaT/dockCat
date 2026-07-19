import Foundation

public actor SystemNotificationPipeline {
    public struct DismissalRequest: Sendable, Equatable {
        public let tokenIdentifier: String
        public let sourceBundleIdentifier: String?
        public let notificationSubtreePath: [Int]
        public let stableContainerIdentifier: String?
    }
    public struct Result: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case enqueued
            case updatedCurrent
            case updatedPending
            case removedCurrent
            case removedPending
            case rejected(AccessibilityNotificationRejection)
            case duplicate
            case queueFull
            case notFound
        }

        public let kind: Kind
        /// The complete actor decision, when this result reached the queue.
        public let queueMutation: NotificationQueue.ExternalMutationResult?

        public init(kind: Kind, queueMutation: NotificationQueue.ExternalMutationResult? = nil) {
            self.kind = kind
            self.queueMutation = queueMutation
        }

        public static let enqueued = Self(kind: .enqueued)
        public static let updatedCurrent = Self(kind: .updatedCurrent)
        public static let updatedPending = Self(kind: .updatedPending)
        public static let removedCurrent = Self(kind: .removedCurrent)
        public static let removedPending = Self(kind: .removedPending)
        public static let duplicate = Self(kind: .duplicate)
        public static let queueFull = Self(kind: .queueFull)
        public static let notFound = Self(kind: .notFound)
        public static func rejected(_ rejection: AccessibilityNotificationRejection) -> Self {
            .init(kind: .rejected(rejection))
        }

        /// Category equality preserves the source-compatible result checks while callers
        /// that coordinate UI consume `queueMutation` rather than issuing another query.
        public static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind }
    }
    private let parser: AccessibilityNotificationParser
    private let exclusions: AccessibilityNotificationExclusionPolicy
    private let tracker: ExternalNotificationLifecycleTracker
    private let queue: NotificationQueue
    private let policy: ExternalPresentationPolicy
    /// Maps callback element identifiers to the parser-selected item identity so
    /// descendant destruction callbacks resolve exactly like appearances.
    private var observationAliases: [String: ExternalNotificationIdentity] = [:]
    private var aliasOrder: [String] = []
    private let aliasLimit = 256
    private var pendingDismissalRequest: DismissalRequest?
    private var runtimeGeneration: UInt64?

    public init(queue: NotificationQueue, ownBundleIdentifier: String,
                parser: AccessibilityNotificationParser = .init(),
                deduplication: NotificationDeduplicationCache = .init(),
                tracker: ExternalNotificationLifecycleTracker = .init()) {
        self.queue = queue; self.parser = parser; self.exclusions = .init(ownBundleIdentifier: ownBundleIdentifier)
        self.tracker = tracker; self.policy = .init()
        _ = deduplication // retained in the source-compatible initializer; lifecycle identity now owns deduplication.
    }

    public func ingest(_ snapshot: AccessibilityNotificationSnapshot, transientDuration: TimeInterval) async -> Result {
        pendingDismissalRequest = nil
        let candidate: AccessibilityNotificationCandidate
        switch parser.parse(snapshot) { case .failure(let rejection): return .rejected(rejection); case .success(let value): candidate = value }
        if snapshot.observationKind == .destroyed {
            let identity = identity(for: candidate, snapshot: snapshot)
            guard case .event(let event) = await tracker.remove(identity) else { return .rejected(.disappeared) }
            removeAliases(for: identity)
            return await apply(event)
        }
        if let rejection = exclusions.rejection(for: candidate) { return .rejected(rejection) }
        let identity = identity(for: candidate, snapshot: snapshot)
        if let observed = snapshot.observedElementIdentifier { rememberAlias(observed, identity: identity) }
        if let token = snapshot.opaqueDismissalTokenIdentifier { rememberAlias(token, identity: identity) }
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
            if result.kind == .queueFull { _ = await tracker.remove(identity) }
            if [.enqueued, .updatedCurrent, .updatedPending].contains(result),
               let token = snapshot.opaqueDismissalTokenIdentifier {
                pendingDismissalRequest = .init(tokenIdentifier: token, sourceBundleIdentifier: candidate.sourceBundleIdentifier,
                                                notificationSubtreePath: candidate.capture.notificationSubtreePath,
                                                stableContainerIdentifier: candidate.capture.stableContainerIdentifier)
            }
            return result
        }
    }

    public func activate(runtimeGeneration: UInt64) {
        self.runtimeGeneration = runtimeGeneration
    }

    /// Invalidates ingress before clearing source lifecycle bookkeeping. Returned tracker
    /// removals are intentionally discarded because global disable clears the queue once.
    public func deactivate() async {
        runtimeGeneration = nil
        pendingDismissalRequest = nil
        _ = await tracker.sourceStopped()
        observationAliases.removeAll(keepingCapacity: true)
        aliasOrder.removeAll(keepingCapacity: true)
    }

    public func ingest(
        _ snapshot: AccessibilityNotificationSnapshot,
        transientDuration: TimeInterval,
        runtimeGeneration generation: UInt64
    ) async -> Result {
        guard runtimeGeneration == generation else { return .notFound }
        pendingDismissalRequest = nil
        let candidate: AccessibilityNotificationCandidate
        switch parser.parse(snapshot) {
        case .failure(let rejection): return .rejected(rejection)
        case .success(let value): candidate = value
        }
        if snapshot.observationKind == .destroyed {
            let identity = identity(for: candidate, snapshot: snapshot)
            guard case .event(let event) = await tracker.remove(identity),
                  runtimeGeneration == generation else { return .rejected(.disappeared) }
            removeAliases(for: identity)
            return await apply(event, runtimeGeneration: generation)
        }
        if let rejection = exclusions.rejection(for: candidate) { return .rejected(rejection) }
        let identity = identity(for: candidate, snapshot: snapshot)
        if let observed = snapshot.observedElementIdentifier { rememberAlias(observed, identity: identity) }
        if let token = snapshot.opaqueDismissalTokenIdentifier { rememberAlias(token, identity: identity) }
        let classification = policy.classify(candidate)
        let presentation: DockCatNotification.Presentation
        let evidence: DockCatNotification.Classification
        switch classification {
        case .transient(let reason): presentation = .transient(duration: transientDuration); evidence = .confident(reason)
        case .persistent(let reason): presentation = .persistent; evidence = .confident(reason)
        case .ambiguous(let reason): presentation = .persistent; evidence = .bestEffort(reason)
        }
        let item = DockCatNotification(
            sourceName: candidate.sourceDisplayName.displayValue ?? "System Notification",
            title: candidate.title.displayValue ?? "", message: candidate.message.displayValue ?? "",
            presentation: presentation, externalIdentity: identity, classification: evidence
        )
        let observation = await tracker.observe(.init(identity: identity, notification: item))
        guard runtimeGeneration == generation else { return .notFound }
        switch observation {
        case .unchanged: return .duplicate
        case .unsupportedOrdering: return .queueFull
        case .event(let event):
            let result = await apply(event, runtimeGeneration: generation)
            if result.kind == .queueFull { _ = await tracker.remove(identity) }
            if [.enqueued, .updatedCurrent, .updatedPending].contains(result),
               let token = snapshot.opaqueDismissalTokenIdentifier {
                pendingDismissalRequest = .init(
                    tokenIdentifier: token,
                    sourceBundleIdentifier: candidate.sourceBundleIdentifier,
                    notificationSubtreePath: candidate.capture.notificationSubtreePath,
                    stableContainerIdentifier: candidate.capture.stableContainerIdentifier
                )
            }
            return result
        }
    }

    /// One-shot handoff ensures an accepted identity is attempted at most once.
    public func takeDismissalRequest() -> DismissalRequest? {
        defer { pendingDismissalRequest = nil }
        return pendingDismissalRequest
    }

    public func sourceStopped() async -> [Result] {
        var results: [Result] = []
        for event in await tracker.sourceStopped() { results.append(await apply(event)) }
        observationAliases.removeAll(keepingCapacity: true)
        aliasOrder.removeAll(keepingCapacity: true)
        return results
    }

    public func sourceStopped(runtimeGeneration generation: UInt64) async -> [Result] {
        guard runtimeGeneration == generation else { return [] }
        var results: [Result] = []
        for event in await tracker.sourceStopped() {
            guard runtimeGeneration == generation else { return results }
            results.append(await apply(event, runtimeGeneration: generation))
        }
        observationAliases.removeAll(keepingCapacity: true)
        aliasOrder.removeAll(keepingCapacity: true)
        return results
    }

    public func reconcile() async -> [Result] {
        var results: [Result] = []
        for event in await tracker.reconcile() { results.append(await apply(event)) }
        return results
    }

    public func reconcile(runtimeGeneration generation: UInt64) async -> [Result] {
        guard runtimeGeneration == generation else { return [] }
        var results: [Result] = []
        for event in await tracker.reconcile() {
            guard runtimeGeneration == generation else { return results }
            results.append(await apply(event, runtimeGeneration: generation))
        }
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
        let kind: Result.Kind
        switch outcome {
        case .inserted: kind = .enqueued
        case .updatedCurrent: kind = .updatedCurrent
        case .updatedPending: kind = .updatedPending
        case .unchangedCurrent, .unchangedPending, .duplicate: kind = .duplicate
        case .removedCurrent: kind = .removedCurrent
        case .removedPending: kind = .removedPending
        case .full: kind = .queueFull
        case .notFound: kind = .notFound
        }
        return .init(kind: kind, queueMutation: outcome)
    }

    private func apply(
        _ event: NotificationSourceEvent,
        runtimeGeneration generation: UInt64
    ) async -> Result {
        guard runtimeGeneration == generation else { return .notFound }
        let outcome: NotificationQueue.ExternalMutationResult
        switch event {
        case .appeared(let value):
            outcome = await queue.enqueueAppeared(value.notification, runtimeGeneration: generation)
        case .updated(let value):
            outcome = await queue.updateExternal(value.notification, runtimeGeneration: generation)
        case .disappeared(let identity):
            outcome = await queue.removeExternal(identity, runtimeGeneration: generation)
        default: return .notFound
        }
        let kind: Result.Kind
        switch outcome {
        case .inserted: kind = .enqueued
        case .updatedCurrent: kind = .updatedCurrent
        case .updatedPending: kind = .updatedPending
        case .unchangedCurrent, .unchangedPending, .duplicate: kind = .duplicate
        case .removedCurrent: kind = .removedCurrent
        case .removedPending: kind = .removedPending
        case .full: kind = .queueFull
        case .notFound: kind = .notFound
        }
        return .init(kind: kind, queueMutation: outcome)
    }

    private func identity(for candidate: AccessibilityNotificationCandidate,
                          snapshot: AccessibilityNotificationSnapshot) -> ExternalNotificationIdentity {
        if let token = snapshot.opaqueDismissalTokenIdentifier, let identity = observationAliases[token] { return identity }
        if let observed = snapshot.observedElementIdentifier, let identity = observationAliases[observed] { return identity }
        let stable: String
        if let container = candidate.capture.stableContainerIdentifier {
            stable = container
        } else {
            // A content fingerprint is preferable to a coarse hierarchy here: it
            // distinguishes simultaneous identical-shaped banners. Subsequent
            // callbacks retain identity through the callback-element alias above.
            stable = "fallback:\(NotificationFingerprint.make(for: candidate).rawValue)"
        }
        return .init(sourceNamespace: "macos.accessibility.notification-center", stableItemIdentifier: stable)
    }

    private func removeAliases(for identity: ExternalNotificationIdentity) {
        observationAliases = observationAliases.filter { $0.value != identity }
        aliasOrder.removeAll { observationAliases[$0] == nil }
    }

    private func rememberAlias(_ alias: String, identity: ExternalNotificationIdentity) {
        if observationAliases[alias] == nil { aliasOrder.append(alias) }
        observationAliases[alias] = identity
        while aliasOrder.count > aliasLimit {
            observationAliases.removeValue(forKey: aliasOrder.removeFirst())
        }
    }
}
