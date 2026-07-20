public struct ApplicationBootstrapGuard: Sendable {
    public private(set) var hasStarted = false

    public init() {}

    /// Returns true exactly once for the lifetime of this guard.
    public mutating func beginIfNeeded() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }
}
