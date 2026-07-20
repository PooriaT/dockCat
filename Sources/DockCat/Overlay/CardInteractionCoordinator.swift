import DockCatCore
import Foundation
import OSLog

@MainActor
final class CardInteractionCoordinator {
    private struct PendingRestoration {
        let decision: CardInteractionExitDecision
        let wasEligibleAtDismissalStart: Bool
    }

    private let focusController: any ApplicationFocusControlling
    private let urlOpener: any CardURLOpening
    private let logger = Logger(
        subsystem: DockCatProductIdentity.osLogSubsystem, category: "CardInteraction"
    )
    private(set) var state = CardInteractionState()
    private var pendingRestoration: PendingRestoration?
    private var explicitExit: CardInteractionExit?

    var onDismissRequested: (() -> Void)?

    init(
        focusController: any ApplicationFocusControlling = ApplicationFocusController(),
        urlOpener: any CardURLOpening = WorkspaceCardURLOpener()
    ) {
        self.focusController = focusController
        self.urlOpener = urlOpener
    }

    func beginPresentation(_ sessionID: PresentationSessionID) {
        state.beginPresentation(sessionID)
        pendingRestoration = nil
        explicitExit = nil
    }

    @discardableResult
    func requestInteraction(
        for sessionID: PresentationSessionID,
        trigger: CardInteractionTrigger,
        setPanelInteractive: () -> Void,
        makePanelKey: (UInt64) -> Void
    ) -> Bool {
        guard state.presentationSessionID == sessionID else {
            logStaleSession(trigger: trigger)
            return false
        }
        if case .interactive = state.mode { return true }

        let wasFrontmost = focusController.isDockCatFrontmost
        let frontmost = focusController.frontmostApplication
        let previousApplication = frontmost.flatMap { application in
            application.processIdentifier == focusController.dockCatProcessIdentifier
                ? nil : application
        }
        let result = state.requestInteraction(
            for: sessionID,
            trigger: trigger,
            previousApplication: previousApplication,
            dockCatBecameActive: false
        )
        guard case .entered(let interaction) = result else { return false }

        logger.info(
            "Card interaction transition=passive-to-interactive generation=\(interaction.generation, privacy: .public) trigger=\(trigger.rawValue, privacy: .public)"
        )
        setPanelInteractive()
        if !wasFrontmost {
            let becameActive = focusController.activateDockCat()
                || focusController.isDockCatFrontmost
            _ = state.recordDockCatActivation(
                for: sessionID,
                interactionGeneration: interaction.generation,
                becameActive: becameActive
            )
        }
        makePanelKey(interaction.generation)
        return true
    }

    func closeRequested(
        for sessionID: PresentationSessionID,
        trigger: CardInteractionTrigger,
        setPanelInteractive: () -> Void,
        makePanelKey: (UInt64) -> Void
    ) {
        guard requestInteraction(
            for: sessionID,
            trigger: trigger,
            setPanelInteractive: setPanelInteractive,
            makePanelKey: makePanelKey
        ) else { return }
        explicitExit = .close
        onDismissRequested?()
    }

    @discardableResult
    func openRequested(
        _ url: URL,
        for sessionID: PresentationSessionID,
        trigger: CardInteractionTrigger,
        setPanelInteractive: () -> Void,
        makePanelKey: (UInt64) -> Void
    ) -> Bool {
        guard url.scheme?.lowercased() == "https",
              requestInteraction(
                for: sessionID,
                trigger: trigger,
                setPanelInteractive: setPanelInteractive,
                makePanelKey: makePanelKey
              ) else { return false }
        guard urlOpener.open(url) else { return false }
        explicitExit = .openAction
        onDismissRequested?()
        return true
    }

    /// Captures a one-shot restoration decision before the panel resigns key. The actual
    /// activation is delayed until CardWindowController has made the panel passive/hidden.
    func prepareExit(
        _ proposedExit: CardInteractionExit,
        for sessionID: PresentationSessionID,
        panelIsKey: Bool
    ) {
        let exit = explicitExit ?? proposedExit
        explicitExit = nil
        let result = state.exit(exit, for: sessionID)
        guard case .exited(let decision) = result else {
            if result == .stalePresentation {
                logger.info(
                    "Card interaction exit=\(exit.rawValue, privacy: .public) restoration=skipped reason=stale-session"
                )
            }
            if result != .noInteraction { pendingRestoration = nil }
            return
        }

        let frontmostPID = focusController.frontmostApplication?.processIdentifier
        let dockCatPID = focusController.dockCatProcessIdentifier
        let noThirdApplicationIsFrontmost = frontmostPID == dockCatPID || panelIsKey
        pendingRestoration = .init(
            decision: decision,
            wasEligibleAtDismissalStart: noThirdApplicationIsFrontmost
        )
        logger.info(
            "Card interaction exit=\(exit.rawValue, privacy: .public) generation=\(decision.session.generation, privacy: .public)"
        )
    }

    func completeExit(for sessionID: PresentationSessionID) {
        guard let pending = pendingRestoration else { return }
        pendingRestoration = nil
        let decision = pending.decision
        guard state.isCurrent(
            interactionGeneration: decision.session.generation,
            presentationSessionID: sessionID
        ) else {
            logRestorationSkipped(decision, reason: "stale-session")
            return
        }
        guard decision.restorationPolicy == .restoreIfSafe else {
            logRestorationSkipped(decision, reason: "open-action-owns-focus")
            return
        }
        guard pending.wasEligibleAtDismissalStart else {
            logRestorationSkipped(decision, reason: "user-switched-apps")
            return
        }
        guard let previous = decision.session.previousApplication else {
            logRestorationSkipped(decision, reason: "no-previous-app")
            return
        }
        guard focusController.isApplicationRunning(previous) else {
            logRestorationSkipped(decision, reason: "previous-app-terminated")
            return
        }

        let frontmostPID = focusController.frontmostApplication?.processIdentifier
        guard frontmostPID == nil
                || frontmostPID == focusController.dockCatProcessIdentifier
                || frontmostPID == previous.processIdentifier else {
            logRestorationSkipped(decision, reason: "user-switched-apps")
            return
        }
        let restored = frontmostPID == previous.processIdentifier
            || focusController.activateApplication(previous)
        logger.info(
            "Card focus restoration generation=\(decision.session.generation, privacy: .public) attempted=true restored=\(restored, privacy: .public)"
        )
    }

    func clearPresentation(_ sessionID: PresentationSessionID) {
        state.clearPresentation(sessionID)
        explicitExit = nil
        pendingRestoration = nil
    }

    private func logStaleSession(trigger: CardInteractionTrigger) {
        logger.info(
            "Card interaction transition=skipped trigger=\(trigger.rawValue, privacy: .public) reason=stale-session"
        )
    }

    private func logRestorationSkipped(
        _ decision: CardInteractionExitDecision,
        reason: String
    ) {
        logger.info(
            "Card focus restoration generation=\(decision.session.generation, privacy: .public) attempted=false reason=\(reason, privacy: .public)"
        )
    }
}
