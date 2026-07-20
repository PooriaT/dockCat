import Foundation

@MainActor
public final class PresentationSessionCoordinator {
    private struct Session {
        let id: PresentationSessionID
        var contentRevision: UInt64 = 0
        var phase: PresentationPhase
        var tasks: [PresentationChildTask: Task<Void, Never>] = [:]
        var transientDuration: Duration?
        var remainingTransientDuration: Duration?
        var timerDeadline: PresentationInstant?
        var hasDeliveredExpiry = false
        var isPaused = false
        var dismissalCause: DismissalCause?
        var cancellationReason: PresentationCancellationReason?
        var pendingExternalUpdateID: UUID?
        var hasPendingExternalDisappearance = false
    }

    private let clock: any PresentationClock
    private var generation: UInt64 = 0
    private var session: Session?

    public init(clock: any PresentationClock = ContinuousPresentationClock()) {
        self.clock = clock
    }

    @discardableResult
    public func startSession(
        notificationID: UUID,
        transientDuration: Duration?,
        phase: PresentationPhase = .waking
    ) -> PresentationSessionID {
        cancelSession(reason: .replacement)
        generation &+= 1
        let id = PresentationSessionID(generation: generation, notificationID: notificationID)
        session = Session(
            id: id,
            phase: phase,
            transientDuration: transientDuration,
            remainingTransientDuration: transientDuration
        )
        return id
    }

    public var activeSessionID: PresentationSessionID? { session?.id }
    public var activePhase: PresentationPhase? { session?.phase }
    public var hasChoreographyTask: Bool { session?.tasks[.choreography] != nil }
    public var hasTimeoutTask: Bool { session?.tasks[.timeout] != nil }

    public func snapshot() -> PresentationSessionSnapshot? {
        guard let session else { return nil }
        return .init(
            id: session.id,
            contentRevision: session.contentRevision,
            phase: session.phase,
            remainingTransientDuration: session.remainingTransientDuration,
            timerDeadline: session.timerDeadline,
            isPaused: session.isPaused,
            dismissalCause: session.dismissalCause,
            cancellationReason: session.cancellationReason,
            pendingExternalUpdateID: session.pendingExternalUpdateID,
            hasPendingExternalDisappearance: session.hasPendingExternalDisappearance
        )
    }

    public func validate(
        _ id: PresentationSessionID,
        notificationID: UUID? = nil,
        phase: PresentationPhase? = nil,
        contentRevision: UInt64? = nil,
        allowDismissing: Bool = false
    ) -> PresentationValidation {
        guard let session, session.id == id else { return .staleSession }
        guard notificationID == nil || notificationID == session.id.notificationID else {
            return .wrongNotification
        }
        guard phase == nil || phase == session.phase else { return .wrongPhase }
        guard contentRevision == nil || contentRevision == session.contentRevision else {
            return .staleContentRevision
        }
        guard allowDismissing || session.dismissalCause == nil else { return .dismissing }
        return .valid
    }

    @discardableResult
    public func beginPhase(_ phase: PresentationPhase, for id: PresentationSessionID) -> Bool {
        guard session?.id == id else { return false }
        session?.phase = phase
        return true
    }

    @discardableResult
    public func replaceContent(
        for id: PresentationSessionID,
        transientDuration: Duration?
    ) -> UInt64? {
        guard session?.id == id, session?.dismissalCause == nil else { return nil }
        session?.contentRevision &+= 1
        session?.transientDuration = transientDuration
        session?.remainingTransientDuration = transientDuration
        session?.timerDeadline = nil
        session?.hasDeliveredExpiry = false
        session?.tasks.removeValue(forKey: .timeout)?.cancel()
        return session?.contentRevision
    }

    public func register(_ task: Task<Void, Never>?, as role: PresentationChildTask, for id: PresentationSessionID) {
        guard session?.id == id else { task?.cancel(); return }
        session?.tasks.removeValue(forKey: role)?.cancel()
        if let task { session?.tasks[role] = task }
    }

    public func clearTask(_ role: PresentationChildTask, for id: PresentationSessionID) {
        guard session?.id == id else { return }
        session?.tasks.removeValue(forKey: role)
    }

    public func cancelTask(_ role: PresentationChildTask, for id: PresentationSessionID) {
        guard session?.id == id else { return }
        session?.tasks.removeValue(forKey: role)?.cancel()
    }

    public func cancelTaskAndWait(_ role: PresentationChildTask, for id: PresentationSessionID) async {
        guard session?.id == id else { return }
        let task = session?.tasks.removeValue(forKey: role)
        task?.cancel()
        await task?.value
    }

    public func cardPresented(
        for id: PresentationSessionID,
        onExpiry: @escaping @MainActor @Sendable (PresentationSessionID) -> Void
    ) async {
        guard session?.id == id else { return }
        session?.phase = .waitingForDismissal
        guard session?.transientDuration != nil else { return }
        if session?.isPaused == true { return }
        await scheduleTimer(for: id, onExpiry: onExpiry)
    }

    public func pause(for id: PresentationSessionID) async {
        guard session?.id == id, session?.isPaused == false else { return }
        session?.isPaused = true
        guard let deadline = session?.timerDeadline else { return }
        let now = await clock.now()
        session?.remainingTransientDuration = max(.zero, deadline - now)
        session?.timerDeadline = nil
        let timeoutTask = session?.tasks.removeValue(forKey: .timeout)
        timeoutTask?.cancel()
        await timeoutTask?.value
    }

    public func resume(
        for id: PresentationSessionID,
        onExpiry: @escaping @MainActor @Sendable (PresentationSessionID) -> Void
    ) async {
        guard session?.id == id, session?.isPaused == true else { return }
        session?.isPaused = false
        guard session?.phase == .waitingForDismissal,
              session?.transientDuration != nil else { return }
        await scheduleTimer(for: id, onExpiry: onExpiry)
    }

    public func beginDismissal(
        sessionID id: PresentationSessionID,
        cause: DismissalCause
    ) -> DismissalDecision {
        guard session?.id == id else { return .staleSession }
        if let winner = session?.dismissalCause { return .alreadyDismissing(winner) }
        session?.dismissalCause = cause
        session?.phase = .dismissingCard
        session?.timerDeadline = nil
        session?.tasks.removeValue(forKey: .timeout)?.cancel()
        return .began(cause)
    }

    public func deferExternalUpdate(notificationID: UUID, for id: PresentationSessionID) {
        guard session?.id == id, session?.hasPendingExternalDisappearance == false else { return }
        session?.pendingExternalUpdateID = notificationID
    }

    public func deferExternalDisappearance(for id: PresentationSessionID) {
        guard session?.id == id else { return }
        session?.hasPendingExternalDisappearance = true
        session?.pendingExternalUpdateID = nil
    }

    public func clearDeferredExternalLifecycle(for id: PresentationSessionID) {
        guard session?.id == id else { return }
        session?.pendingExternalUpdateID = nil
        session?.hasPendingExternalDisappearance = false
    }

    @discardableResult
    public func cancelSession(reason: PresentationCancellationReason) -> [Task<Void, Never>] {
        guard var old = session else { return [] }
        old.cancellationReason = reason
        session = nil
        let tasks = Array(old.tasks.values)
        for task in tasks { task.cancel() }
        return tasks
    }

    /// Invalidates the session before cancellation, then waits until every owned child task
    /// has observed cancellation. Late completions therefore fail session validation.
    public func cancelSessionAndWait(reason: PresentationCancellationReason) async {
        let tasks = cancelSession(reason: reason)
        for task in tasks { await task.value }
    }

    public func finishSession(_ id: PresentationSessionID) {
        guard session?.id == id else { return }
        session?.phase = .finished
        cancelSession(reason: .finished)
    }

    private func scheduleTimer(
        for id: PresentationSessionID,
        onExpiry: @escaping @MainActor @Sendable (PresentationSessionID) -> Void
    ) async {
        guard session?.id == id,
              session?.hasDeliveredExpiry == false,
              let remaining = session?.remainingTransientDuration else { return }
        session?.tasks.removeValue(forKey: .timeout)?.cancel()
        if remaining <= .zero {
            session?.remainingTransientDuration = .zero
            session?.hasDeliveredExpiry = true
            onExpiry(id)
            return
        }
        let deadline = await clock.now() + remaining
        guard session?.id == id, session?.isPaused == false else { return }
        session?.timerDeadline = deadline
        let clock = self.clock
        let task = Task { @MainActor [weak self] in
            do { try await clock.sleep(until: deadline) } catch { return }
            guard !Task.isCancelled,
                  self?.validate(id, phase: .waitingForDismissal) == .valid,
                  self?.session?.isPaused == false,
                  self?.session?.hasDeliveredExpiry == false else { return }
            self?.session?.timerDeadline = nil
            self?.session?.remainingTransientDuration = .zero
            self?.session?.hasDeliveredExpiry = true
            self?.session?.tasks.removeValue(forKey: .timeout)
            onExpiry(id)
        }
        session?.tasks[.timeout] = task
    }
}
