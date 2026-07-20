import Combine
import DockCatCore
import Foundation
import OSLog

enum MenuBarRecoveryConfigurationError: String, Error, Equatable {
    case urlSchemeMissing
    case settingsCommandRejected
    case settingsPresenterUnavailable

    var userMessage: String {
        switch self {
        case .urlSchemeMissing:
            "DockCat's recovery URL is not registered in this app build. Keep the menu item visible and reinstall or rebuild DockCat."
        case .settingsCommandRejected:
            "DockCat's recovery command is unavailable in this app build. Keep the menu item visible and update DockCat."
        case .settingsPresenterUnavailable:
            "DockCat cannot open its Settings window in this app build. Keep the menu item visible and update DockCat."
        }
    }
}

@MainActor
protocol MenuBarRecoveryConfigurationChecking {
    func verify() -> Result<Void, MenuBarRecoveryConfigurationError>
}

@MainActor
struct MenuBarRecoveryConfigurationVerifier: MenuBarRecoveryConfigurationChecking {
    var registeredURLSchemes: () -> [String]
    var settingsCommandIsAccepted: () -> Bool
    var settingsPresenterIsAvailable: () -> Bool

    init(
        bundle: Bundle = .main,
        parser: DockCatURLCommandParser = .init(),
        settingsPresenterIsAvailable: @escaping () -> Bool
    ) {
        registeredURLSchemes = {
            guard let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
                return []
            }
            return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        }
        settingsCommandIsAccepted = {
            guard let url = URL(string: "dockcat://settings") else { return false }
            return (try? parser.parse(url)) == .openSettings(restoreMenuBar: false)
        }
        self.settingsPresenterIsAvailable = settingsPresenterIsAvailable
    }

    init(
        registeredURLSchemes: @escaping () -> [String],
        settingsCommandIsAccepted: @escaping () -> Bool,
        settingsPresenterIsAvailable: @escaping () -> Bool
    ) {
        self.registeredURLSchemes = registeredURLSchemes
        self.settingsCommandIsAccepted = settingsCommandIsAccepted
        self.settingsPresenterIsAvailable = settingsPresenterIsAvailable
    }

    func verify() -> Result<Void, MenuBarRecoveryConfigurationError> {
        guard registeredURLSchemes().contains(where: { $0.caseInsensitiveCompare("dockcat") == .orderedSame }) else {
            return .failure(.urlSchemeMissing)
        }
        guard settingsCommandIsAccepted() else { return .failure(.settingsCommandRejected) }
        guard settingsPresenterIsAvailable() else { return .failure(.settingsPresenterUnavailable) }
        return .success(())
    }
}

@MainActor
final class MenuBarVisibilityController: ObservableObject {
    static let preferenceKey = "DockCat.menuBarVisible"
    static let recoveryCommand = "open 'dockcat://settings?restoreMenuBar=1'"

    @Published private(set) var isVisible: Bool
    @Published private(set) var isHideConfirmationPending = false
    @Published private(set) var recoveryConfigurationError: MenuBarRecoveryConfigurationError?

    var isChanging: Bool { isHideConfirmationPending }

    private let defaults: UserDefaults
    private let recoveryConfiguration: MenuBarRecoveryConfigurationChecking
    private let logger = Logger(subsystem: DockCatProductIdentity.osLogSubsystem, category: "Recovery")

    init(
        defaults: UserDefaults = .standard,
        recoveryConfiguration: MenuBarRecoveryConfigurationChecking
    ) {
        self.defaults = defaults
        self.recoveryConfiguration = recoveryConfiguration
        if defaults.object(forKey: Self.preferenceKey) != nil {
            isVisible = defaults.bool(forKey: Self.preferenceKey)
        } else {
            isVisible = true
        }
    }

    func requestVisibility(_ visible: Bool) {
        if visible {
            restore()
            return
        }
        guard isVisible, !isHideConfirmationPending else { return }
        switch recoveryConfiguration.verify() {
        case .success:
            recoveryConfigurationError = nil
            isHideConfirmationPending = true
            logger.info("URL recovery configuration verified result=available")
        case .failure(let error):
            recoveryConfigurationError = error
            logger.error("URL recovery configuration verified result=\(error.rawValue, privacy: .public)")
        }
    }

    func confirmHide() {
        guard isVisible, isHideConfirmationPending else { return }
        switch recoveryConfiguration.verify() {
        case .success:
            isHideConfirmationPending = false
            setVisible(false)
        case .failure(let error):
            isHideConfirmationPending = false
            recoveryConfigurationError = error
            logger.error("Menu visibility transition blocked reason=\(error.rawValue, privacy: .public)")
        }
    }

    func cancelHide() {
        guard isHideConfirmationPending else { return }
        isHideConfirmationPending = false
    }

    func restore() {
        isHideConfirmationPending = false
        recoveryConfigurationError = nil
        setVisible(true)
    }

    func dismissRecoveryConfigurationError() {
        recoveryConfigurationError = nil
    }

    private func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        defaults.set(visible, forKey: Self.preferenceKey)
        logger.info("Menu visibility transition visible=\(visible, privacy: .public)")
    }
}
