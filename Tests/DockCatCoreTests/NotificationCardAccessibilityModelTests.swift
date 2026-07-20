import Foundation
import Testing
@testable import DockCatCore

struct NotificationCardAccessibilityModelTests {
    @Test func semanticRegionsAreSeparateOrderedAndStable() {
        let model = makeModel()

        #expect(model.orderedElements.map(\.role) == [
            .secondaryContext, .summary, .heading, .staticText, .status, .button, .button
        ])
        #expect(model.orderedElements.map(\.identifier) == [
            "dockcat.card.source", "dockcat.card.behavior", "dockcat.card.title",
            "dockcat.card.message", "dockcat.card.queue", "dockcat.card.open",
            "dockcat.card.close"
        ])
        #expect(model.orderedElements[2].role == .heading)
        #expect(NotificationCardAccessibilityIdentifier.allCases.allSatisfy {
            !$0.rawValue.contains("Invented") && !$0.rawValue.contains("Private")
        })
    }

    @Test func emptyMessageAndZeroQueueAreOmitted() {
        let model = makeModel(message: "", queue: .empty)
        #expect(model.messageLabel == nil)
        #expect(model.queueLabel == nil)
        #expect(!model.orderedElements.contains { $0.role == .staticText })
        #expect(!model.orderedElements.contains { $0.role == .status })
    }

    @Test func behaviorAndQueueCopyAreDeterministic() {
        let persistent = makeModel(presentation: .persistent)
        #expect(persistent.behaviorLabel.contains("Remains until dismissed"))

        let transient = makeModel(presentation: .transient)
        #expect(transient.behaviorLabel == "Transient. Closes automatically.")
        #expect(!transient.behaviorLabel.contains("5"))

        #expect(makeModel(queue: .init(pendingCount: 1, isDeliveryPaused: false)).queueLabel
            == "One additional notification waiting.")
        #expect(makeModel(queue: .init(pendingCount: 3, isDeliveryPaused: false)).queueLabel
            == "3 additional notifications waiting.")
        #expect(makeModel(queue: .init(pendingCount: 0, isDeliveryPaused: true)).queueLabel
            == "Delivery paused.")
    }

    @Test func controlsNeverExposeURLAndRespectAvailability() {
        let model = makeModel(hasOpen: true, canDismiss: true)
        #expect(model.openControl?.label == "Open notification")
        #expect(model.openControl?.hint.contains("https://") == false)
        #expect(model.closeControl?.label == "Dismiss notification")
        #expect(makeModel(hasOpen: false, canDismiss: false).openControl == nil)
        #expect(makeModel(hasOpen: false, canDismiss: false).closeControl == nil)
    }

    @Test func arrivalDoesNotReadPrivateContent() {
        let transient = makeModel(presentation: .transient, queue: .init(
            pendingCount: 2, isDeliveryPaused: false
        ))
        #expect(transient.arrivalAnnouncement
            == "DockCat notification from Invented Source. Transient. 2 more notifications waiting.")
        #expect(!transient.arrivalAnnouncement.contains("Private Title"))
        #expect(!transient.arrivalAnnouncement.contains("Private Body"))
        let persistent = makeModel(presentation: .persistent)
        #expect(persistent.arrivalAnnouncement.contains("Persistent."))
    }

    private func makeModel(
        message: String = "Private Body",
        presentation: CardPresentationKind = .transient,
        queue: CardQueueContext = .init(pendingCount: 2, isDeliveryPaused: false),
        hasOpen: Bool = true,
        canDismiss: Bool = true
    ) -> NotificationCardAccessibilityModel {
        .init(content: .init(
            notificationID: UUID(uuidString: "00000000-0000-0000-0000-000000000087")!,
            sourceName: "Invented Source",
            title: "Private Title",
            message: message,
            presentation: presentation,
            hasOpenAction: hasOpen,
            canDismiss: canDismiss,
            queueContext: queue
        ))
    }
}
