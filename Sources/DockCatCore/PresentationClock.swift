import Foundation

public struct PresentationInstant: Comparable, Hashable, Sendable {
    public let offset: Duration

    public init(offset: Duration) { self.offset = offset }
    public static let zero = PresentationInstant(offset: .zero)

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
    public static func + (lhs: Self, rhs: Duration) -> Self { .init(offset: lhs.offset + rhs) }
    public static func - (lhs: Self, rhs: Self) -> Duration { lhs.offset - rhs.offset }
}

public protocol PresentationClock: Sendable {
    func now() async -> PresentationInstant
    func sleep(until deadline: PresentationInstant) async throws
}

public struct ContinuousPresentationClock: PresentationClock, Sendable {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    public init() { origin = clock.now }

    public func now() async -> PresentationInstant {
        PresentationInstant(offset: origin.duration(to: clock.now))
    }

    public func sleep(until deadline: PresentationInstant) async throws {
        try await clock.sleep(until: origin.advanced(by: deadline.offset))
    }
}

public actor ManualPresentationClock: PresentationClock {
    private struct Waiter {
        let deadline: PresentationInstant
        let continuation: CheckedContinuation<Void, Never>
    }

    private var instant: PresentationInstant
    private var waiters: [UUID: Waiter] = [:]

    public init(now: PresentationInstant = .zero) { instant = now }

    public func now() -> PresentationInstant { instant }

    public func sleep(until deadline: PresentationInstant) async throws {
        if deadline <= instant { return }
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled || deadline <= instant {
                    continuation.resume()
                } else {
                    waiters[id] = Waiter(deadline: deadline, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        try Task.checkCancellation()
    }

    public func advance(by duration: Duration) {
        precondition(duration >= .zero)
        advance(to: instant + duration)
    }

    public func advance(to target: PresentationInstant) {
        precondition(target >= instant)
        instant = target
        let ready = waiters.filter { $0.value.deadline <= target }
        for (id, waiter) in ready {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    public var pendingWaiterCount: Int { waiters.count }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.continuation.resume()
    }
}
