import Foundation

public struct DockCatDiagnosticEvent: Codable, Equatable, Sendable {
    public enum Category: String, Codable, Equatable, Sendable, CaseIterable {
        case runtimeTransition, catTransition, effect, queueMutation, presentationPhase, sourceHealth, placementRefresh, recovery, staleCallbackRejected, sourceToggle, deliveryPause, catAssetPipeline
    }
    public enum Outcome: String, Codable, Equatable, Sendable, CaseIterable { case requested, started, completed, cancelled, failed, rejected, changed, unchanged }
    public let sequence: UInt64
    public let timestamp: Date
    public let category: Category
    public let outcome: Outcome
    public let detail: String?
    public let revision: UInt64?
    public let generation: UInt64?
    public init(sequence: UInt64, timestamp: Date, category: Category, outcome: Outcome, detail: String? = nil, revision: UInt64? = nil, generation: UInt64? = nil) {
        self.sequence = sequence; self.timestamp = timestamp; self.category = category; self.outcome = outcome; self.detail = detail; self.revision = revision; self.generation = generation
    }
}

public actor DockCatDiagnosticEventRecorder {
    public let capacity: Int
    private var nextSequence: UInt64 = 1
    private var events: [DockCatDiagnosticEvent] = []
    public init(capacity: Int = 100) { self.capacity = max(1, capacity) }
    @discardableResult public func record(category: DockCatDiagnosticEvent.Category, outcome: DockCatDiagnosticEvent.Outcome, detail: String? = nil, revision: UInt64? = nil, generation: UInt64? = nil, timestamp: Date = Date()) -> DockCatDiagnosticEvent {
        let event = DockCatDiagnosticEvent(sequence: nextSequence, timestamp: timestamp, category: category, outcome: outcome, detail: detail, revision: revision, generation: generation)
        nextSequence &+= 1; events.append(event); if events.count > capacity { events.removeFirst(events.count - capacity) }; return event
    }
    public func snapshot() -> [DockCatDiagnosticEvent] { events }
    public func clear() { events.removeAll() }
}
