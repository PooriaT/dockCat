import AppKit
import DockCatCore
import Foundation

@MainActor
protocol DockCatSettingsProviding: AnyObject {
    var preferences: DockCatPreferences { get set }
    var effectiveAnimationPreferences: EffectiveAnimationPreferences { get }
    var accessibilityDisplayOptions: AccessibilityDisplayOptionsMonitor { get }
}

protocol NotificationQueueing: Sendable {
    func snapshot() async -> NotificationQueueSnapshot
    func activateRuntimeGeneration(_ generation: UInt64) async
    func enqueue(_ notification: DockCatNotification, runtimeGeneration generation: UInt64) async -> NotificationQueue.EnqueueResult
    func enqueueAppeared(_ notification: DockCatNotification, runtimeGeneration generation: UInt64) async -> NotificationQueue.ExternalMutationResult
    func updateExternal(_ notification: DockCatNotification, runtimeGeneration generation: UInt64) async -> NotificationQueue.ExternalMutationResult
    func removeExternal(_ identity: ExternalNotificationIdentity, runtimeGeneration generation: UInt64) async -> NotificationQueue.ExternalMutationResult
    func claimNext() async -> NotificationQueue.ClaimResult
    func completeCurrent(policy: NotificationQueue.CompletionPolicy) async -> NotificationQueue.CompletionResult
    func setPaused(_ value: Bool) async -> NotificationQueue.PauseResult
    func setLimit(_ value: Int, runtimeGeneration generation: UInt64) async -> NotificationQueue.LimitResult
    func clearForGlobalDisable() async -> NotificationQueue.ClearResult
}

@MainActor
protocol CatVisualDriving: AnyObject {
    var isVisible: Bool { get }
    @discardableResult func applyVisualPreferences(_ preferences: EffectiveAnimationPreferences) -> Bool
    func updatePlacement(_ placement: DockPlacement, logicalState: CatLogicalPlacement, sessionID: PresentationSessionID?) -> CatPlacementUpdateOutcome
    func showSleeping(using placement: DockPlacement)
    func hideOverlay()
    func resetVisualStateWhileHidden()
    func resetToSleeping()
    func animate(_ animation: CatAnimation, preferences: EffectiveAnimationPreferences, sessionID: PresentationSessionID) async -> PresentationAnimationResult
    func pause()
    func resume()
    func cancelVisualWork()
    func showCarriedCard()
    func hideCarriedCard()
    func prepareHandoffPose()
    func completeHandoffPose()
    func handoffSourceRect() -> CGRect
    func presentationExclusionFrame() -> CGRect
}

@MainActor
protocol CardPresenting: AnyObject {
    var onDismiss: (() -> Void)? { get set }
    var validateInteractionSession: ((PresentationSessionID) -> Bool)? { get set }
    func updatePlacementContext(_ context: CardPlacementContext, logicalState: CatLogicalPlacement, dismissalSourceRect: CGRect?) -> CardPlacementUpdateOutcome
    func updateQueueContext(_ context: CardQueueContext, revision: NotificationQueueRevision)
    func cancelPresentationAnimation()
    func applyVisualPreferences(_ preferences: EffectiveAnimationPreferences)
    func applyAccessibilityDisplayOptions(_ options: AccessibilityDisplayOptions)
    func forceHide(exit: CardInteractionExit)
    func present(notification: DockCatNotification, preferences: DockCatPreferences, from sourceRect: CGRect, visualPreferences: EffectiveAnimationPreferences, sessionID: PresentationSessionID) async -> PresentationAnimationResult
    func replace(notification: DockCatNotification, preferences: DockCatPreferences, visualPreferences: EffectiveAnimationPreferences, sessionID: PresentationSessionID) async -> PresentationAnimationResult
    func dismissActive(toward sourceRect: CGRect?, visualPreferences: EffectiveAnimationPreferences, sessionID: PresentationSessionID) async -> PresentationAnimationResult
    func prepareForDismissal(exit: CardInteractionExit, sessionID: PresentationSessionID)
    func announceStableCard(sessionID: PresentationSessionID, contentRevision: UInt64, category: CardAccessibilityAnnouncementCategory)
}

@MainActor
protocol DockPlacementProviding: AnyObject {
    func locate(preferences: DockCatPreferences, catalog: DisplayCatalog, safeToRestoreSpecific: Bool) -> DockPlacement?
}

@MainActor
protocol CalibrationPreviewing: AnyObject {
    func start(with placement: DockPlacement)
    func update(_ placement: DockPlacement)
    func stop()
}

@MainActor
protocol SystemNotificationSourceAccessing: AnyObject {
    var health: SystemNotificationSourceHealth { get }
    var generation: UInt64 { get }
    func setEnabled(_ enabled: Bool)
    func setRuntimeAllowed(_ allowed: Bool)
    func refresh()
    func requestPermission()
    func shutdown()
    func acceptsCallback(generation: UInt64) -> Bool
    func sourceDidLosePermission()
    func sourceDidStart()
    func sourceDidDegrade()
    func sourceDidBecomeUnavailable()
}

protocol SystemNotificationPipelineHandling: Sendable {
    func activate(runtimeGeneration: UInt64) async
    func deactivate() async
    func ingest(_ snapshot: AccessibilityNotificationSnapshot, transientDuration: TimeInterval, runtimeGeneration generation: UInt64) async -> SystemNotificationPipeline.Result
    func takeDismissalRequest() async -> SystemNotificationPipeline.DismissalRequest?
    func sourceStopped(runtimeGeneration generation: UInt64) async -> [SystemNotificationPipeline.Result]
    func reconcile(runtimeGeneration generation: UInt64) async -> [SystemNotificationPipeline.Result]
}

@MainActor
protocol NativeBannerDismissalPerforming: AnyObject {
    func perform(token: String, sourceBundleIdentifier: String?, notificationSubtreePath: [Int], stableContainerIdentifier: String?, excluded: Set<String>, ownBundleIdentifier: String) -> NativeBannerDismissalPerformer.Outcome
}

@MainActor
protocol DisplayCatalogProviding: AnyObject { var onChange: (@MainActor () -> Void)? { get set }; func stop() }

@MainActor
protocol DockCatEventLogging: AnyObject {
    func runtimeTransition(previous: DockCatRuntimeMode, next: DockCatRuntimeMode, generation: UInt64)
    func catTransition(previous: CatState, event: CatEvent, next: CatState, effect: CatCoordinatorEffect)
    func catTransitionRejected(state: CatState, event: CatEvent, reason: CatTransitionRejection.Reason)
    func staleCallbackRejected(category: String)
    func recovery(context: String, previous: CatState, safe: CatState)
    func info(_ message: String)
    func error(_ message: String)
    func fault(_ message: String)
}

@MainActor
protocol SystemNotificationSourceEventBinding: AnyObject {
    func bind(generatedEventHandler: @escaping @MainActor (NotificationSourceEvent, UInt64) -> Void, outcomeHandler: @escaping @MainActor (SystemNotificationAccessibilitySource.Outcome) -> Void)
    func unbind()
}

@MainActor
struct AppStateDependencies {
    let settings: any DockCatSettingsProviding
    let displayCatalog: DisplayCatalog
    let queue: any NotificationQueueing
    let catDriver: any CatVisualDriving
    let cardPresenter: any CardPresenting
    let placementProvider: any DockPlacementProviding
    let calibrationPreview: any CalibrationPreviewing
    let presentation: PresentationSessionCoordinator
    let systemAccess: any SystemNotificationSourceAccessing
    let sourceEvents: (any SystemNotificationSourceEventBinding)?
    let systemPipeline: any SystemNotificationPipelineHandling
    let nativeBannerDismissal: any NativeBannerDismissalPerforming
    let logger: any DockCatEventLogging
    let retainedObjects: [AnyObject]
}

extension NotificationQueue: NotificationQueueing {}
extension SettingsStore: DockCatSettingsProviding {}
extension CatWindowController: CatVisualDriving {}
extension CardWindowController: CardPresenting {}
extension DockLocator: DockPlacementProviding {}
extension DockCalibrationPreviewController: CalibrationPreviewing {}
extension DisplayCatalog: DisplayCatalogProviding {}
extension SystemNotificationAccessController: SystemNotificationSourceAccessing {}
extension SystemNotificationPipeline: SystemNotificationPipelineHandling {}
