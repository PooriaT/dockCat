import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class CardAccessibilityAnnouncerTests: XCTestCase {
    func testArrivalUpdateAndDuplicatePolicyArePrivacySafe() async {
        let delivery = AccessibilityAnnouncementDeliveryFake()
        let announcer = CardAccessibilityAnnouncer(delivery: delivery)
        let session = PresentationSessionID(
            generation: 7,
            notificationID: UUID(uuidString: "00000000-0000-0000-0000-000000000087")!
        )
        let model = makeModel()

        announcer.announceStable(
            model: model, sessionID: session, contentRevision: 0, category: .arrival
        )
        try? await Task.sleep(for: .milliseconds(10))
        announcer.announceStable(
            model: model, sessionID: session, contentRevision: 0, category: .arrival
        )
        announcer.announceStable(
            model: model, sessionID: session, contentRevision: 1,
            category: .contentUpdate
        )
        try? await Task.sleep(for: .milliseconds(10))

        XCTAssertEqual(delivery.values, [
            "DockCat notification from Invented Source. Transient.",
            "DockCat notification updated."
        ])
        XCTAssertFalse(delivery.values.joined().contains("Private"))
    }

    func testCancellationPreventsPendingDelivery() async {
        let delivery = AccessibilityAnnouncementDeliveryFake()
        let announcer = CardAccessibilityAnnouncer(delivery: delivery)
        announcer.announceStable(
            model: makeModel(),
            sessionID: .init(generation: 8, notificationID: UUID()),
            contentRevision: 0,
            category: .arrival
        )
        announcer.cancelPending(reason: "global-disable")
        await Task.yield()
        await Task.yield()
        XCTAssertTrue(delivery.values.isEmpty)
    }

    func testBridgeExposesRolesAndAppliesAppearanceWithoutReplacingSession() async {
        let controller = CardWindowController(
            accessibilityAnnouncementDelivery: AccessibilityAnnouncementDeliveryFake()
        )
        let notification = DockCatNotification(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000087")!,
            sourceName: "Invented Source",
            title: "Invented Title",
            message: "Invented Body",
            presentation: .persistent,
            actionURL: URL(string: "https://example.invalid/action")
        )
        let session = PresentationSessionID(generation: 1, notificationID: notification.id)
        controller.validateInteractionSession = { $0 == session }
        _ = await controller.present(
            notification: notification,
            preferences: DockCatPreferences(),
            from: .zero,
            reducedMotion: true,
            sessionID: session
        )
        let originalSequence = controller.operationSequenceForTesting
        let originalHostingView = controller.hostingViewIdentityForTesting

        XCTAssertEqual(controller.accessibilityModelForTesting?.orderedElements.map(\.role), [
            .secondaryContext, .summary, .heading, .staticText, .button, .button
        ])
        XCTAssertEqual(
            controller.accessibilityModelForTesting?.orderedElements.map(\.identifier),
            [
                "dockcat.card.source", "dockcat.card.behavior", "dockcat.card.title",
                "dockcat.card.message", "dockcat.card.open", "dockcat.card.close"
            ]
        )

        controller.applyAccessibilityDisplayOptions(.init(
            reduceMotion: false,
            increaseContrast: true,
            reduceTransparency: true,
            differentiateWithoutColor: true
        ))
        XCTAssertEqual(
            controller.accessibilityAppearanceForTesting?.backgroundStyle,
            .opaqueSystem
        )
        XCTAssertEqual(controller.operationSequenceForTesting, originalSequence)
        XCTAssertEqual(controller.installedNotificationIDForTesting, notification.id)
        XCTAssertEqual(controller.hostingViewIdentityForTesting, originalHostingView)

        controller.requestAccessibilityInteractionForTesting()
        guard case .interactive(let interaction) = controller.interactionModeForTesting else {
            return XCTFail("Valid VoiceOver interaction should enter interactive mode")
        }
        XCTAssertEqual(interaction.trigger, .accessibility)
        controller.forceHide(exit: .globalDisable)
    }

    private func makeModel() -> NotificationCardAccessibilityModel {
        .init(content: .init(
            notificationID: UUID(), sourceName: "Invented Source",
            title: "Private Title", message: "Private Body", presentation: .transient,
            hasOpenAction: false, canDismiss: true, queueContext: .empty
        ))
    }
}

@MainActor
private final class AccessibilityAnnouncementDeliveryFake: CardAccessibilityAnnouncementDelivering {
    var values: [String] = []
    func deliver(_ announcement: String) { values.append(announcement) }
}
