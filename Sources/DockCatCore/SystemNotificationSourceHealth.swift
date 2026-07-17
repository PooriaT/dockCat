public struct SystemNotificationSourceHealth: Sendable, Equatable {
    public enum State: String, Sendable, CaseIterable {
        case disabled, permissionRequired, starting, active, degraded, unavailable
    }

    public enum Reason: String, Sendable, Equatable {
        case permissionMissing
        case permissionRevoked
        case observerNotImplemented
        case compatibilityProblem
        case startupFailed
        case processUnavailable
        case noUsefulNotifications
    }

    public let state: State
    public let reason: Reason?

    public init(_ state: State, reason: Reason? = nil) {
        self.state = state
        self.reason = reason
    }

    public var isEnabled: Bool { state != .disabled }
    public var isHealthy: Bool { state == .active }
    public var isRetryable: Bool { state == .permissionRequired || state == .degraded || state == .unavailable }
    public var isTerminal: Bool { state == .disabled }
}
