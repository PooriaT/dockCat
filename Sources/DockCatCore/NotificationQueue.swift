import Foundation

public actor NotificationQueue {
    public typealias EnqueueResult = NotificationQueueEnqueueResult
    public typealias ClaimResult = NotificationQueueClaimResult
    public typealias CompletionPolicy = NotificationQueueCompletionPolicy
    public typealias CompletionResult = NotificationQueueCompletionResult
    public typealias PauseResult = NotificationQueuePauseResult
    public typealias LimitResult = NotificationQueueLimitResult
    public typealias ClearResult = NotificationQueueClearResult
    public typealias ExternalMutationResult = NotificationQueueExternalMutationResult
    public typealias ExternalLocation = NotificationQueueExternalLocation

    private var pending: [DockCatNotification] = []
    private var current: DockCatNotification?
    private var activeIDs: Set<UUID> = []
    private var recentCompletions: RecentNotificationIDCache
    private var paused = false
    private var revision: NotificationQueueRevision = 0
    private var limit: Int
    private var runtimeGeneration: UInt64?

    public init(limit: Int = 20, recentCompletionCapacity: Int = 256) {
        self.limit = max(1, limit)
        recentCompletions = .init(capacity: recentCompletionCapacity)
    }

    public func snapshot() -> NotificationQueueSnapshot {
        .init(
            isPaused: paused,
            currentID: current?.id,
            pendingCount: pending.count,
            limit: limit,
            revision: revision,
            recentCompletionCount: recentCompletions.count,
            recentCompletionCapacity: recentCompletions.capacity
        )
    }

    public func enqueue(_ notification: DockCatNotification) -> EnqueueResult {
        guard !isDuplicate(notification.id) else { return .duplicate(revision: revision) }
        guard storedCount < limit else { return .full(revision: revision) }
        activeIDs.insert(notification.id)
        pending.append(notification)
        didMutate()
        return .accepted(revision: revision)
    }

    public func activateRuntimeGeneration(_ generation: UInt64) {
        runtimeGeneration = generation
    }

    public func enqueue(
        _ notification: DockCatNotification,
        runtimeGeneration generation: UInt64
    ) -> EnqueueResult {
        guard runtimeGeneration == generation else { return .duplicate(revision: revision) }
        return enqueue(notification)
    }

    public func enqueueAppeared(_ notification: DockCatNotification) -> ExternalMutationResult {
        guard let identity = notification.externalIdentity else { return .notFound(revision: revision) }
        guard location(of: identity) == nil else { return .duplicate(revision: revision) }
        switch enqueue(notification) {
        case .accepted:
            return .inserted(notification: notification, index: pending.count - 1, revision: revision)
        case .duplicate:
            return .duplicate(revision: revision)
        case .full:
            return .full(revision: revision)
        }
    }

    public func enqueueAppeared(
        _ notification: DockCatNotification,
        runtimeGeneration generation: UInt64
    ) -> ExternalMutationResult {
        guard runtimeGeneration == generation else { return .notFound(revision: revision) }
        return enqueueAppeared(notification)
    }

    public func updateExternal(_ notification: DockCatNotification) -> ExternalMutationResult {
        guard let identity = notification.externalIdentity else { return .notFound(revision: revision) }
        if let old = current, old.externalIdentity == identity {
            let updated = notification.preservingIdentity(of: old)
            guard updated != old else { return .unchangedCurrent(notification: old, revision: revision) }
            current = updated
            didMutate()
            return .updatedCurrent(notification: updated, revision: revision)
        }
        guard let index = pending.firstIndex(where: { $0.externalIdentity == identity }) else {
            return .notFound(revision: revision)
        }
        let updated = notification.preservingIdentity(of: pending[index])
        guard updated != pending[index] else {
            return .unchangedPending(notification: pending[index], index: index, revision: revision)
        }
        pending[index] = updated
        didMutate()
        return .updatedPending(notification: updated, index: index, revision: revision)
    }

    public func updateExternal(
        _ notification: DockCatNotification,
        runtimeGeneration generation: UInt64
    ) -> ExternalMutationResult {
        guard runtimeGeneration == generation else { return .notFound(revision: revision) }
        return updateExternal(notification)
    }

    public func removeExternal(_ identity: ExternalNotificationIdentity) -> ExternalMutationResult {
        if let current, current.externalIdentity == identity {
            self.current = nil
            activeIDs.remove(current.id)
            didMutate()
            return .removedCurrent(notification: current, pendingCount: pending.count, revision: revision)
        }
        guard let index = pending.firstIndex(where: { $0.externalIdentity == identity }) else {
            return .notFound(revision: revision)
        }
        let removed = pending.remove(at: index)
        activeIDs.remove(removed.id)
        didMutate()
        return .removedPending(notification: removed, index: index, revision: revision)
    }

    public func removeExternal(
        _ identity: ExternalNotificationIdentity,
        runtimeGeneration generation: UInt64
    ) -> ExternalMutationResult {
        guard runtimeGeneration == generation else { return .notFound(revision: revision) }
        return removeExternal(identity)
    }

    public func location(of identity: ExternalNotificationIdentity) -> ExternalLocation? {
        if current?.externalIdentity == identity { return .current }
        return pending.firstIndex(where: { $0.externalIdentity == identity }).map(ExternalLocation.pending)
    }

    public func claimNext() -> ClaimResult {
        if paused { return .paused(current: current, pendingCount: pending.count, revision: revision) }
        if let current { return .current(current, revision: revision) }
        guard !pending.isEmpty else { return .idle(revision: revision) }
        current = pending.removeFirst()
        didMutate()
        return .promoted(current!, revision: revision)
    }

    public func completeCurrent(policy: CompletionPolicy) -> CompletionResult {
        guard let completed = current else { return .noCurrent(revision: revision) }
        current = nil
        activeIDs.remove(completed.id)
        recentCompletions.insert(completed.id)

        let result: CompletionResult
        if paused {
            result = .pausedAfterCompletion(
                completed: completed,
                pendingCount: pending.count,
                revision: nextRevision
            )
        } else if policy == .advanceImmediately, !pending.isEmpty {
            current = pending.removeFirst()
            result = .advanced(completed: completed, next: current!, revision: nextRevision)
        } else if pending.isEmpty {
            result = .completedAndIdle(completed: completed, revision: nextRevision)
        } else {
            result = .completedWithPending(
                completed: completed,
                pendingCount: pending.count,
                revision: nextRevision
            )
        }
        didMutate()
        return result
    }

    public func setPaused(_ value: Bool) -> PauseResult {
        guard paused != value else {
            return .unchanged(isPaused: paused, currentID: current?.id, pendingCount: pending.count, revision: revision)
        }
        paused = value
        didMutate()
        return .changed(isPaused: paused, currentID: current?.id, pendingCount: pending.count, revision: revision)
    }

    public func setLimit(_ value: Int) -> LimitResult {
        let normalized = max(1, value)
        guard normalized != limit else { return .unchanged(current: limit, revision: revision) }
        let previous = limit
        limit = normalized
        didMutate()
        return .changed(previous: previous, current: limit, revision: revision)
    }

    public func setLimit(
        _ value: Int,
        runtimeGeneration generation: UInt64
    ) -> LimitResult {
        guard runtimeGeneration == generation else {
            return .unchanged(current: limit, revision: revision)
        }
        return setLimit(value)
    }

    /// Atomically removes all deliverable work and resets delivery pause for global disable.
    /// Recent completions are deliberately retained to prevent replay after re-enable.
    public func clearForGlobalDisable() -> ClearResult {
        runtimeGeneration = nil
        let removedCurrentID = current?.id
        let removedPendingCount = pending.count
        let changed = current != nil || !pending.isEmpty || paused
        guard changed else {
            return .init(
                removedCurrentID: nil,
                removedPendingCount: 0,
                revision: revision,
                didChange: false
            )
        }
        current = nil
        pending.removeAll(keepingCapacity: true)
        activeIDs.removeAll(keepingCapacity: true)
        paused = false
        didMutate()
        return .init(
            removedCurrentID: removedCurrentID,
            removedPendingCount: removedPendingCount,
            revision: revision,
            didChange: true
        )
    }

    private var storedCount: Int { pending.count + (current == nil ? 0 : 1) }
    private var nextRevision: NotificationQueueRevision {
        precondition(revision < .max, "Notification queue revision exhausted")
        return revision + 1
    }

    private func isDuplicate(_ id: UUID) -> Bool {
        activeIDs.contains(id) || recentCompletions.contains(id)
    }

    private func didMutate() {
        revision = nextRevision
        assert(activeIDs == Set(pending.map(\.id) + [current?.id].compactMap { $0 }))
        assert(storedCount == activeIDs.count)
        assert(recentCompletions.count <= recentCompletions.capacity)
    }
}

private extension DockCatNotification {
    func preservingIdentity(of old: DockCatNotification) -> DockCatNotification {
        .init(
            id: old.id,
            sourceName: sourceName,
            title: title,
            message: message,
            presentation: presentation,
            actionURL: actionURL,
            createdAt: old.createdAt,
            externalIdentity: externalIdentity,
            classification: classification
        )
    }
}
