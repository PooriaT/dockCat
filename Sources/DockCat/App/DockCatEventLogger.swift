import DockCatCore
import OSLog

@MainActor
final class OSLogDockCatEventLogger: DockCatEventLogging {
    private let logger: Logger
    init(category: String = "AppState") { logger = Logger(subsystem: "com.example.DockCat", category: category) }
    func runtimeTransition(previous: DockCatRuntimeMode, next: DockCatRuntimeMode, generation: UInt64) { logger.info("Runtime transition previous=\(previous.rawValue, privacy: .public) next=\(next.rawValue, privacy: .public) generation=\(generation, privacy: .public)") }
    func catTransition(previous: CatState, event: CatEvent, next: CatState, effect: CatCoordinatorEffect) { logger.info("Cat transition previous=\(previous.rawValue, privacy: .public) event=\(event.rawValue, privacy: .public) next=\(next.rawValue, privacy: .public) effect=\(effect.rawValue, privacy: .public)") }
    func catTransitionRejected(state: CatState, event: CatEvent, reason: CatTransitionRejection.Reason) { logger.error("Cat transition rejected state=\(state.rawValue, privacy: .public) event=\(event.rawValue, privacy: .public) reason=\(reason.rawValue, privacy: .public) recovery=true") }
    func staleCallbackRejected(category: String) { logger.info("Stale source callback rejected category=\(category, privacy: .public)") }
    func recovery(context: String, previous: CatState, safe: CatState) { logger.fault("Cat coordinator recovered previous=\(previous.rawValue, privacy: .public) safe=\(safe.rawValue, privacy: .public) context=\(context, privacy: .public)") }
    func info(_ message: String) { logger.info("\(message, privacy: .public)") }
    func error(_ message: String) { logger.error("\(message, privacy: .public)") }
    func fault(_ message: String) { logger.fault("\(message, privacy: .public)") }
}
