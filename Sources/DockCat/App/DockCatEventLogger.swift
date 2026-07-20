import DockCatCore
import OSLog

@MainActor
final class OSLogDockCatEventLogger: DockCatEventLogging {
    private let logger: Logger
    private let diagnosticRecorder: DockCatDiagnosticEventRecorder?

    init(
        category: String = "AppState",
        diagnosticRecorder: DockCatDiagnosticEventRecorder? = nil
    ) {
        logger = Logger(subsystem: DockCatProductIdentity.osLogSubsystem, category: category)
        self.diagnosticRecorder = diagnosticRecorder
    }

    func runtimeTransition(previous: DockCatRuntimeMode, next: DockCatRuntimeMode, generation: UInt64) {
        logger.info("Runtime transition previous=\(previous.rawValue, privacy: .public) next=\(next.rawValue, privacy: .public) generation=\(generation, privacy: .public)")
        record(.runtimeTransition, outcome: .changed, detail: "\(previous.rawValue)->\(next.rawValue)", generation: generation)
    }

    func catTransition(previous: CatState, event: CatEvent, next: CatState, effect: CatCoordinatorEffect) {
        logger.info("Cat transition previous=\(previous.rawValue, privacy: .public) event=\(event.rawValue, privacy: .public) next=\(next.rawValue, privacy: .public) effect=\(effect.rawValue, privacy: .public)")
        record(.catTransition, outcome: .changed, detail: "\(previous.rawValue)->\(next.rawValue)")
        record(.effect, outcome: .started, detail: effect.rawValue)
    }

    func catTransitionRejected(state: CatState, event: CatEvent, reason: CatTransitionRejectionReason) {
        logger.error("Cat transition rejected state=\(state.rawValue, privacy: .public) event=\(event.rawValue, privacy: .public) reason=\(reason.rawValue, privacy: .public) recovery=true")
        record(.catTransition, outcome: .rejected, detail: reason.rawValue)
    }

    func staleCallbackRejected(category: String) {
        logger.info("Stale source callback rejected category=\(category, privacy: .public)")
        record(.staleCallbackRejected, outcome: .rejected, detail: Self.safeStaleCallbackDetail(category))
    }

    func recovery(context: String, previous: CatState, safe: CatState) {
        logger.fault("Cat coordinator recovered previous=\(previous.rawValue, privacy: .public) safe=\(safe.rawValue, privacy: .public) context=\(context, privacy: .public)")
        record(.recovery, outcome: .completed, detail: "\(previous.rawValue)->\(safe.rawValue)")
    }

    func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    func fault(_ message: String) { logger.fault("\(message, privacy: .public)") }

    private static func safeStaleCallbackDetail(_ category: String) -> String {
        switch category {
        case "runtime-generation", "runtime-mode": category
        default: "other"
        }
    }

    private func record(
        _ category: DockCatDiagnosticEvent.Category,
        outcome: DockCatDiagnosticEvent.Outcome,
        detail: String? = nil,
        revision: UInt64? = nil,
        generation: UInt64? = nil
    ) {
        guard let diagnosticRecorder else { return }
        Task {
            await diagnosticRecorder.record(
                category: category,
                outcome: outcome,
                detail: detail,
                revision: revision,
                generation: generation
            )
        }
    }
}
