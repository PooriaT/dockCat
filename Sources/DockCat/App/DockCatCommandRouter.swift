import DockCatCore
import OSLog

@MainActor
final class DockCatCommandRouter {
    typealias NotificationSubmission = @MainActor (DockCatNotification) -> Void
    typealias MenuBarRestoration = @MainActor () -> Void
    typealias SettingsPresentation = @MainActor (SettingsOpenRequestSource) -> Void

    private let submitNotification: NotificationSubmission
    private let restoreMenuBar: MenuBarRestoration
    private let presentSettings: SettingsPresentation
    private let logger = Logger(subsystem: DockCatProductIdentity.osLogSubsystem, category: "Recovery")

    init(
        submitNotification: @escaping NotificationSubmission,
        restoreMenuBar: @escaping MenuBarRestoration,
        presentSettings: @escaping SettingsPresentation
    ) {
        self.submitNotification = submitNotification
        self.restoreMenuBar = restoreMenuBar
        self.presentSettings = presentSettings
    }

    func route(_ command: DockCatURLCommand, source: SettingsOpenRequestSource = .url) {
        switch command {
        case .notify(let notification):
            submitNotification(notification)
        case .openSettings(let shouldRestoreMenuBar):
            if shouldRestoreMenuBar { restoreMenuBar() }
            presentSettings(source)
            logger.info("Recovery command handled category=settings restore=\(shouldRestoreMenuBar, privacy: .public)")
        case .restoreMenuBar:
            restoreMenuBar()
            presentSettings(source)
            logger.info("Recovery command handled category=restore-menu-bar")
        }
    }

    func route(_ command: ApplicationRecoveryCommand) {
        switch command {
        case .showSettings:
            presentSettings(.commandLine)
            logger.info("Recovery command handled category=show-settings")
        case .restoreMenuBar:
            restoreMenuBar()
            presentSettings(.commandLine)
            logger.info("Recovery command handled category=restore-menu-bar")
        }
    }
}
