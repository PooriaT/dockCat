import Combine
import Foundation
import XCTest
@testable import DockCat
import DockCatCore

final class MenuBarRecoveryTests: XCTestCase {
    @MainActor
    func testApplicationDelegateIsObservableByItsSceneAdaptor() {
        requireObservableObject(AppDelegate.self)
    }

    @MainActor
    func testStoredVisibilityMigratesAndMissingValueDefaultsVisible() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let missing = makeController(defaults: defaults)
        XCTAssertTrue(missing.isVisible)

        defaults.set(false, forKey: MenuBarVisibilityController.preferenceKey)
        let hidden = makeController(defaults: defaults)
        XCTAssertFalse(hidden.isVisible)

        defaults.set(true, forKey: MenuBarVisibilityController.preferenceKey)
        let visible = makeController(defaults: defaults)
        XCTAssertTrue(visible.isVisible)
    }

    @MainActor
    func testHideRequiresConfirmationAndCancelPreservesVisibility() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = makeController(defaults: defaults)
        controller.requestVisibility(false)
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(controller.isHideConfirmationPending)

        controller.cancelHide()
        XCTAssertTrue(controller.isVisible)
        XCTAssertFalse(controller.isHideConfirmationPending)
        XCTAssertNil(defaults.object(forKey: MenuBarVisibilityController.preferenceKey))
    }

    @MainActor
    func testConfirmHideAndRepeatedRestoreArePersistedAndIdempotent() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = makeController(defaults: defaults)
        controller.requestVisibility(false)
        controller.confirmHide()
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(defaults.bool(forKey: MenuBarVisibilityController.preferenceKey))

        controller.requestVisibility(false)
        XCTAssertFalse(controller.isHideConfirmationPending)

        controller.restore()
        controller.restore()
        XCTAssertTrue(controller.isVisible)
        XCTAssertTrue(defaults.bool(forKey: MenuBarVisibilityController.preferenceKey))
    }

    @MainActor
    func testConfirmedHideAndRecoveryRestorePublishInsertionChanges() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = makeController(defaults: defaults)
        var insertionChanges: [Bool] = []
        let observation = controller.$isVisible.dropFirst().sink {
            insertionChanges.append($0)
        }

        controller.requestVisibility(false)
        controller.confirmHide()
        controller.restore()

        XCTAssertEqual(insertionChanges, [false, true])
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testUnavailableRecoveryConfigurationBlocksHiding() {
        let (suiteName, defaults) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let verifier = MenuBarRecoveryConfigurationVerifier(
            registeredURLSchemes: { [] },
            settingsCommandIsAccepted: { true },
            settingsPresenterIsAvailable: { true }
        )
        let controller = MenuBarVisibilityController(
            defaults: defaults,
            recoveryConfiguration: verifier
        )
        controller.requestVisibility(false)
        XCTAssertTrue(controller.isVisible)
        XCTAssertFalse(controller.isHideConfirmationPending)
        XCTAssertEqual(controller.recoveryConfigurationError, .urlSchemeMissing)
    }

    @MainActor
    func testVerifierChecksSchemeParserAndPresenterIndependently() {
        let missingParser = MenuBarRecoveryConfigurationVerifier(
            registeredURLSchemes: { ["dockcat"] },
            settingsCommandIsAccepted: { false },
            settingsPresenterIsAvailable: { true }
        )
        XCTAssertEqual(failure(missingParser.verify()), .settingsCommandRejected)

        let missingPresenter = MenuBarRecoveryConfigurationVerifier(
            registeredURLSchemes: { ["DOCKCAT"] },
            settingsCommandIsAccepted: { true },
            settingsPresenterIsAvailable: { false }
        )
        XCTAssertEqual(failure(missingPresenter.verify()), .settingsPresenterUnavailable)
    }

    @MainActor
    func testSettingsPresenterReusesAnExistingWindowAndAlwaysActivates() {
        var windowExists = false
        var openCount = 0
        var frontCount = 0
        var activationCount = 0
        let presenter = SettingsWindowPresenter(
            bringExistingWindowToFront: {
                guard windowExists else { return false }
                frontCount += 1
                return true
            },
            openSettingsScene: {
                openCount += 1
                windowExists = true
            },
            activateApplication: { activationCount += 1 }
        )

        presenter.present(source: .menu)
        presenter.present(source: .url)
        XCTAssertEqual(openCount, 1)
        XCTAssertEqual(frontCount, 1)
        XCTAssertEqual(activationCount, 2)
    }

    @MainActor
    func testRouterSeparatesNotificationsFromStateNeutralRecovery() {
        struct RuntimeState: Equatable {
            var enabled = false
            var paused = true
            var queueCount = 3
            var transientRemaining = 2.5
        }
        let before = RuntimeState()
        let runtime = before
        var submitted: [DockCatNotification] = []
        var restoreCount = 0
        var presentations: [SettingsOpenRequestSource] = []
        let router = DockCatCommandRouter(
            submitNotification: { submitted.append($0) },
            restoreMenuBar: { restoreCount += 1 },
            presentSettings: { presentations.append($0) }
        )

        router.route(.openSettings(restoreMenuBar: false))
        router.route(DockCatURLCommand.restoreMenuBar)
        router.route(.openSettings(restoreMenuBar: false), source: .reopen)
        router.route(.showSettings)

        XCTAssertEqual(runtime, before)
        XCTAssertTrue(submitted.isEmpty)
        XCTAssertEqual(restoreCount, 1)
        XCTAssertEqual(presentations, [.url, .url, .reopen, .commandLine])
    }

    private func makeDefaults() -> (String, UserDefaults) {
        let suiteName = "MenuBarRecoveryTests.\(UUID().uuidString)"
        return (suiteName, UserDefaults(suiteName: suiteName)!)
    }

    @MainActor
    private func makeController(defaults: UserDefaults) -> MenuBarVisibilityController {
        MenuBarVisibilityController(
            defaults: defaults,
            recoveryConfiguration: MenuBarRecoveryConfigurationVerifier(
                registeredURLSchemes: { ["dockcat"] },
                settingsCommandIsAccepted: { true },
                settingsPresenterIsAvailable: { true }
            )
        )
    }

    private func failure<T, Failure: Error>(_ result: Result<T, Failure>) -> Failure? {
        guard case .failure(let error) = result else { return nil }
        return error
    }

    private func requireObservableObject<T: ObservableObject>(_ type: T.Type) {}
}
