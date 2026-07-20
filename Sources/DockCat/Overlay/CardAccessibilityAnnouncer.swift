import AppKit
import DockCatCore
import OSLog

@MainActor
protocol CardAccessibilityAnnouncementDelivering: AnyObject {
    func deliver(_ announcement: String)
}

@MainActor
final class AppKitCardAccessibilityAnnouncementDelivery: CardAccessibilityAnnouncementDelivering {
    func deliver(_ announcement: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

enum CardAccessibilityAnnouncementCategory: String, Equatable {
    case arrival
    case contentUpdate
}

@MainActor
final class CardAccessibilityAnnouncer {
    private struct Key: Hashable {
        let sessionGeneration: UInt64
        let contentRevision: UInt64
        let category: CardAccessibilityAnnouncementCategory
    }

    private let delivery: any CardAccessibilityAnnouncementDelivering
    private let logger = Logger(
        subsystem: DockCatProductIdentity.osLogSubsystem, category: "CardAccessibility"
    )
    private var pendingTask: Task<Void, Never>?
    private var pendingKey: Key?
    private var deliveredKeys: Set<Key> = []

    init(
        delivery: any CardAccessibilityAnnouncementDelivering = AppKitCardAccessibilityAnnouncementDelivery()
    ) {
        self.delivery = delivery
    }

    func announceStable(
        model: NotificationCardAccessibilityModel,
        sessionID: PresentationSessionID,
        contentRevision: UInt64,
        category: CardAccessibilityAnnouncementCategory
    ) {
        let key = Key(
            sessionGeneration: sessionID.generation,
            contentRevision: contentRevision,
            category: category
        )
        guard pendingKey != key, !deliveredKeys.contains(key) else {
            logger.info(
                "Announcement suppressed category=\(category.rawValue, privacy: .public) generation=\(sessionID.generation, privacy: .public) reason=duplicate"
            )
            return
        }
        cancelPending(reason: "superseded")
        pendingKey = key
        let text = category == .arrival
            ? model.arrivalAnnouncement
            : CardAccessibilityCopy.updatedAnnouncement
        pendingTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.pendingKey == key else { return }
            self.pendingTask = nil
            self.pendingKey = nil
            self.deliveredKeys.insert(key)
            self.delivery.deliver(text)
            self.logger.info(
                "Announcement delivered category=\(category.rawValue, privacy: .public) generation=\(sessionID.generation, privacy: .public)"
            )
        }
    }

    func cancelPending(reason: String) {
        guard pendingTask != nil else { return }
        pendingTask?.cancel()
        pendingTask = nil
        pendingKey = nil
        logger.info(
            "Announcement suppressed category=pending reason=\(reason, privacy: .public)"
        )
    }
}
