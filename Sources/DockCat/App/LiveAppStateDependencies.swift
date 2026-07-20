import DockCatCore
import Foundation

@MainActor
private final class LiveSystemNotificationEventRouter: SystemNotificationSourceEventBinding {
    private var generatedEventHandler: @MainActor (NotificationSourceEvent, UInt64) -> Void = { _, _ in }
    private var outcomeHandler: @MainActor (SystemNotificationAccessibilitySource.Outcome) -> Void = { _ in }
    func bind(generatedEventHandler: @escaping @MainActor (NotificationSourceEvent, UInt64) -> Void, outcomeHandler: @escaping @MainActor (SystemNotificationAccessibilitySource.Outcome) -> Void) {
        self.generatedEventHandler = generatedEventHandler
        self.outcomeHandler = outcomeHandler
    }
    func unbind() {
        generatedEventHandler = { _, _ in }
        outcomeHandler = { _ in }
    }
    func emit(_ event: NotificationSourceEvent, generation: UInt64) { generatedEventHandler(event, generation) }
    func emit(_ outcome: SystemNotificationAccessibilitySource.Outcome) { outcomeHandler(outcome) }
}


@MainActor
extension AppStateDependencies {
    static func live(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? DockCatProductIdentity.fallbackBundleIdentifier) -> AppStateDependencies {
        let settings = SettingsStore()
        let displayCatalog = DisplayCatalog()
        let queue = NotificationQueue()
        let registry = AccessibilityElementRegistry()
        let eventRouter = LiveSystemNotificationEventRouter()
        let source = SystemNotificationAccessibilitySource(dismissalRegistry: registry, generatedEventHandler: { event, generation in eventRouter.emit(event, generation: generation) }, outcomeHandler: { outcome in eventRouter.emit(outcome) })
        let access = SystemNotificationAccessController(enabled: settings.preferences.systemNotificationsEnabled, runtimeAllowed: false, source: source, startImmediately: false)
        let pipeline = SystemNotificationPipeline(queue: queue, ownBundleIdentifier: bundleIdentifier)
        let nativeDismissal = NativeBannerDismissalPerformer(registry: registry, client: AccessibilityAPIClient())
        return .init(settings: settings, displayCatalog: displayCatalog, queue: queue, catDriver: CatWindowController(), cardPresenter: CardWindowController(), placementProvider: DockLocator(), calibrationPreview: DockCalibrationPreviewController(), presentation: PresentationSessionCoordinator(clock: ContinuousPresentationClock()), systemAccess: access, sourceEvents: eventRouter, systemPipeline: pipeline, nativeBannerDismissal: nativeDismissal, logger: OSLogDockCatEventLogger(), retainedObjects: [source])
    }
}
