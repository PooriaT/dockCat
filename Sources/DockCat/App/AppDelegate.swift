import AppKit
import Combine
import DockCatCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let state = AppState(dependencies: .live())
    let diagnosticRecorder = DockCatDiagnosticEventRecorder()
    lazy var settingsPresenter = SettingsWindowPresenter()
    lazy var menuBarVisibility = MenuBarVisibilityController(
        recoveryConfiguration: MenuBarRecoveryConfigurationVerifier(
            settingsPresenterIsAvailable: { [weak self] in
                self?.settingsPresenter.isAvailable == true
            }
        )
    )

    private lazy var commandRouter = DockCatCommandRouter(
        submitNotification: { [weak state] in state?.submit($0) },
        restoreMenuBar: { [weak self] in self?.menuBarVisibility.restore() },
        presentSettings: { [weak self] source in self?.settingsPresenter.present(source: source) }
    )
    private var terminationTask: Task<Void, Never>?
    private var bootstrapGuard = ApplicationBootstrapGuard()
    private var commandsAwaitingBootstrap: [DockCatURLCommand] = []
    private var menuBarVisibilityObservation: AnyCancellable?
    private let logger = Logger(subsystem: DockCatProductIdentity.osLogSubsystem, category: "Recovery")

    override init() {
        super.init()
        // NSApplicationDelegateAdaptor observes an ObservableObject delegate. Forward the
        // controller's changes so the App scene reevaluates MenuBarExtra's insertion binding.
        menuBarVisibilityObservation = menuBarVisibility.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard bootstrapGuard.beginIfNeeded() else {
            logger.error("Bootstrap duplicate-start rejected")
            return
        }
        NSApp.setActivationPolicy(.accessory)
        state.start()

        let queuedCommands = commandsAwaitingBootstrap
        commandsAwaitingBootstrap.removeAll()
        let argumentResult = Result {
            try ApplicationRecoveryCommandParser().parse(Array(ProcessInfo.processInfo.arguments.dropFirst()))
        }
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            queuedCommands.forEach { self.commandRouter.route($0) }
            switch argumentResult {
            case .success(let commands):
                commands.forEach { self.commandRouter.route($0) }
            case .failure(let error):
                let category = (error as? ApplicationRecoveryCommandParseError)?.rawValue
                    ?? ApplicationRecoveryCommandParseError.unsupportedArgument.rawValue
                self.logger.error("Recovery arguments rejected category=\(category, privacy: .public)")
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do {
                let command = try DockCatURLCommandParser(
                    defaultDuration: state.settings.preferences.defaultTransientDuration
                ).parse(url)
                if bootstrapGuard.hasStarted {
                    commandRouter.route(command)
                } else {
                    commandsAwaitingBootstrap.append(command)
                }
            } catch {
                let category = (error as? DockCatURLCommandParseError)?.rawValue
                    ?? DockCatURLCommandParseError.malformedURL.rawValue
                logger.error("URL command rejected category=\(category, privacy: .public)")
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        commandRouter.route(.openSettings(restoreMenuBar: false), source: .reopen)
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        state.systemNotificationAccess.refresh()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task { @MainActor [state] in
            await state.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
