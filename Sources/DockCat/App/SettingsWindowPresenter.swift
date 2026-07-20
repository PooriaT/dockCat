import AppKit
import OSLog

enum SettingsOpenRequestSource: String, Equatable, Sendable {
    case menu
    case url
    case reopen
    case commandLine = "command-line"
    case hideConfirmationHelp = "hide-confirmation-help"
}

/// The sole bridge from app-lifecycle code to SwiftUI's Settings scene.
@MainActor
final class SettingsWindowPresenter {
    typealias BringExistingWindowToFront = @MainActor () -> Bool
    typealias OpenSettingsScene = @MainActor () -> Void
    typealias ActivateApplication = @MainActor () -> Void

    private let bringExistingWindowToFront: BringExistingWindowToFront
    private let openSettingsScene: OpenSettingsScene
    private let activateApplication: ActivateApplication
    private let logger = Logger(subsystem: "com.example.DockCat", category: "Recovery")

    let isAvailable: Bool

    init(
        isAvailable: Bool = true,
        bringExistingWindowToFront: @escaping BringExistingWindowToFront = {
            guard let window = NSApp.windows.first(where: {
                $0.isVisible && $0.level == .normal && $0.styleMask.contains(.titled)
            }) else { return false }
            window.makeKeyAndOrderFront(nil)
            return true
        },
        openSettingsScene: @escaping OpenSettingsScene = {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        },
        activateApplication: @escaping ActivateApplication = {
            NSApp.activate(ignoringOtherApps: true)
        }
    ) {
        self.isAvailable = isAvailable
        self.bringExistingWindowToFront = bringExistingWindowToFront
        self.openSettingsScene = openSettingsScene
        self.activateApplication = activateApplication
    }

    func present(source: SettingsOpenRequestSource) {
        let reusedExistingWindow = bringExistingWindowToFront()
        if !reusedExistingWindow { openSettingsScene() }
        activateApplication()
        logger.info(
            "Settings open requested source=\(source.rawValue, privacy: .public) reused=\(reusedExistingWindow, privacy: .public)"
        )
    }
}
