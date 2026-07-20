import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class CardInteractionCoordinatorTests: XCTestCase {
    func testExplicitInteractionCapturesAndActivatesOnce() {
        let focus = FocusControllerFake(frontmostPID: 200)
        let coordinator = CardInteractionCoordinator(
            focusController: focus, urlOpener: URLOpenerFake()
        )
        let sessionID = makeSessionID()
        coordinator.beginPresentation(sessionID)
        var focusGenerations: [UInt64] = []
        var events: [String] = []
        focus.onActivateDockCat = { events.append("activate") }

        XCTAssertTrue(coordinator.requestInteraction(
            for: sessionID, trigger: .pointer,
            setPanelInteractive: { events.append("eligible") },
            makePanelKey: {
                events.append("key")
                focusGenerations.append($0)
            }
        ))
        XCTAssertTrue(coordinator.requestInteraction(
            for: sessionID, trigger: .pointer,
            setPanelInteractive: { events.append("eligible") },
            makePanelKey: { focusGenerations.append($0) }
        ))

        XCTAssertEqual(focus.activateDockCatCount, 1)
        XCTAssertEqual(focusGenerations, [1])
        XCTAssertEqual(events, ["eligible", "activate", "key"])
        guard case .interactive(let interaction) = coordinator.state.mode else {
            return XCTFail("Expected interactive mode")
        }
        XCTAssertEqual(interaction.previousApplication?.processIdentifier, 200)
        XCTAssertTrue(interaction.dockCatBecameActive)
    }

    func testInteractiveCloseRestoresPreviousRunningApplicationOnce() {
        let focus = FocusControllerFake(frontmostPID: 200)
        let coordinator = CardInteractionCoordinator(
            focusController: focus, urlOpener: URLOpenerFake()
        )
        let sessionID = makeSessionID()
        coordinator.beginPresentation(sessionID)
        var dismissCount = 0
        coordinator.onDismissRequested = { dismissCount += 1 }
        coordinator.closeRequested(
            for: sessionID, trigger: .pointer,
            setPanelInteractive: {}, makePanelKey: { _ in }
        )

        coordinator.prepareExit(.close, for: sessionID, panelIsKey: true)
        XCTAssertEqual(focus.activatedApplicationPIDs, [])
        coordinator.completeExit(for: sessionID)
        coordinator.completeExit(for: sessionID)

        XCTAssertEqual(dismissCount, 1)
        XCTAssertEqual(focus.activatedApplicationPIDs, [200])
    }

    func testSuccessfulOpenDismissesWithoutRestoringOldFocus() {
        let focus = FocusControllerFake(frontmostPID: 200)
        let opener = URLOpenerFake(result: true)
        let coordinator = CardInteractionCoordinator(
            focusController: focus, urlOpener: opener
        )
        let sessionID = makeSessionID()
        coordinator.beginPresentation(sessionID)
        var dismissCount = 0
        coordinator.onDismissRequested = { dismissCount += 1 }

        XCTAssertTrue(coordinator.openRequested(
            URL(string: "https://example.com")!,
            for: sessionID, trigger: .pointer,
            setPanelInteractive: {}, makePanelKey: { _ in }
        ))
        coordinator.prepareExit(.close, for: sessionID, panelIsKey: true)
        coordinator.completeExit(for: sessionID)

        XCTAssertEqual(opener.openedURLs.count, 1)
        XCTAssertEqual(dismissCount, 1)
        XCTAssertTrue(focus.activatedApplicationPIDs.isEmpty)
    }

    func testFailedOrUnsafeOpenKeepsCardInteractive() {
        let focus = FocusControllerFake(frontmostPID: 200)
        let opener = URLOpenerFake(result: false)
        let coordinator = CardInteractionCoordinator(
            focusController: focus, urlOpener: opener
        )
        let sessionID = makeSessionID()
        coordinator.beginPresentation(sessionID)
        var dismissCount = 0
        coordinator.onDismissRequested = { dismissCount += 1 }

        XCTAssertFalse(coordinator.openRequested(
            URL(string: "https://example.com")!,
            for: sessionID, trigger: .pointer,
            setPanelInteractive: {}, makePanelKey: { _ in }
        ))
        XCTAssertFalse(coordinator.openRequested(
            URL(string: "http://example.com")!,
            for: sessionID, trigger: .pointer,
            setPanelInteractive: {}, makePanelKey: { _ in }
        ))

        XCTAssertEqual(dismissCount, 0)
        XCTAssertEqual(opener.openedURLs.count, 1)
        guard case .interactive = coordinator.state.mode else {
            return XCTFail("A failed Open must retain interaction")
        }
    }

    func testThirdApplicationOrTerminatedTargetSuppressesRestoration() {
        for targetIsRunning in [true, false] {
            let focus = FocusControllerFake(frontmostPID: 200)
            let coordinator = CardInteractionCoordinator(
                focusController: focus, urlOpener: URLOpenerFake()
            )
            let sessionID = makeSessionID()
            coordinator.beginPresentation(sessionID)
            _ = coordinator.requestInteraction(
                for: sessionID, trigger: .pointer,
                setPanelInteractive: {}, makePanelKey: { _ in }
            )
            focus.runningPIDs = targetIsRunning ? [100, 200, 300] : [100, 300]
            focus.frontmostPID = targetIsRunning ? 300 : 100

            coordinator.prepareExit(.sourceDismissal, for: sessionID, panelIsKey: false)
            coordinator.completeExit(for: sessionID)

            XCTAssertTrue(focus.activatedApplicationPIDs.isEmpty)
        }
    }

    func testPanelKeyEligibilityAndEscapeAreGuarded() {
        let panel = CardOverlayPanel()
        var dismissCount = 0
        panel.onCancelRequested = { dismissCount += 1 }

        XCTAssertFalse(panel.canBecomeKey)
        panel.cancelOperation(nil)
        panel.enterInteractiveMode()
        XCTAssertTrue(panel.canBecomeKey)
        panel.activeCardIsDismissible = true
        panel.cancelOperation(nil)

        XCTAssertEqual(dismissCount, 0, "A non-key panel must ignore Escape")
        panel.returnToPassiveMode()
        XCTAssertFalse(panel.canBecomeKey)
    }

    func testPresentationReplacementAndMetadataUpdatesRemainPassive() async {
        let controller = CardWindowController()
        let first = DockCatNotification(
            sourceName: "test", title: "First", message: "Passive"
        )
        let firstSession = PresentationSessionID(
            generation: 1, notificationID: first.id
        )

        _ = await controller.present(
            notification: first,
            preferences: DockCatPreferences(),
            from: .zero,
            reducedMotion: true,
            sessionID: firstSession
        )
        controller.updateQueueContext(
            .init(pendingCount: 2, isDeliveryPaused: false), revision: 1
        )

        XCTAssertEqual(controller.interactionModeForTesting, .passive)
        XCTAssertFalse(controller.panelCanBecomeKeyForTesting)
        XCTAssertFalse(controller.panelIsKeyForTesting)

        let second = DockCatNotification(
            sourceName: "test", title: "Second", message: "Still passive"
        )
        let secondSession = PresentationSessionID(
            generation: 2, notificationID: second.id
        )
        _ = await controller.replace(
            notification: second,
            preferences: DockCatPreferences(),
            reducedMotion: true,
            sessionID: secondSession
        )

        XCTAssertEqual(controller.interactionModeForTesting, .passive)
        XCTAssertFalse(controller.panelCanBecomeKeyForTesting)
        XCTAssertFalse(controller.panelIsKeyForTesting)
        controller.forceHide(exit: .globalDisable)
    }

    private func makeSessionID() -> PresentationSessionID {
        PresentationSessionID(generation: 1, notificationID: UUID())
    }
}

@MainActor
private final class FocusControllerFake: ApplicationFocusControlling {
    let dockCatProcessIdentifier: Int32 = 100
    var frontmostPID: Int32?
    var runningPIDs: Set<Int32> = [100, 200, 300]
    var activateDockCatCount = 0
    var activatedApplicationPIDs: [Int32] = []
    var onActivateDockCat: (() -> Void)?

    init(frontmostPID: Int32?) {
        self.frontmostPID = frontmostPID
    }

    var frontmostApplication: CardApplicationIdentity? {
        frontmostPID.map(CardApplicationIdentity.init(processIdentifier:))
    }

    var isDockCatFrontmost: Bool {
        frontmostPID == dockCatProcessIdentifier
    }

    func activateDockCat() -> Bool {
        activateDockCatCount += 1
        onActivateDockCat?()
        frontmostPID = dockCatProcessIdentifier
        return true
    }

    func isApplicationRunning(_ identity: CardApplicationIdentity) -> Bool {
        runningPIDs.contains(identity.processIdentifier)
    }

    func activateApplication(_ identity: CardApplicationIdentity) -> Bool {
        guard isApplicationRunning(identity) else { return false }
        activatedApplicationPIDs.append(identity.processIdentifier)
        frontmostPID = identity.processIdentifier
        return true
    }
}

@MainActor
private final class URLOpenerFake: CardURLOpening {
    var result: Bool
    var openedURLs: [URL] = []

    init(result: Bool = true) {
        self.result = result
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return result
    }
}
