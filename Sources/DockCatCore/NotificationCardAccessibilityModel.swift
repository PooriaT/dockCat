import Foundation

public enum NotificationCardAccessibilityIdentifier: String, CaseIterable, Sendable {
    case container = "dockcat.card"
    case source = "dockcat.card.source"
    case behavior = "dockcat.card.behavior"
    case title = "dockcat.card.title"
    case message = "dockcat.card.message"
    case queue = "dockcat.card.queue"
    case open = "dockcat.card.open"
    case close = "dockcat.card.close"
}

public enum CardAccessibilityElementRole: String, Equatable, Sendable {
    case secondaryContext
    case summary
    case heading
    case staticText
    case status
    case button
}

public struct CardAccessibilityElement: Equatable, Sendable {
    public let role: CardAccessibilityElementRole
    public let label: String
    public let value: String?
    public let hint: String?
    public let identifier: String

    public init(
        role: CardAccessibilityElementRole,
        label: String,
        value: String? = nil,
        hint: String? = nil,
        identifier: String
    ) {
        self.role = role
        self.label = label
        self.value = value
        self.hint = hint
        self.identifier = identifier
    }
}

public struct CardAccessibilityControl: Equatable, Sendable {
    public let label: String
    public let hint: String
    public let identifier: String

    public init(label: String, hint: String, identifier: String) {
        self.label = label
        self.hint = hint
        self.identifier = identifier
    }
}

public struct NotificationCardAccessibilityModel: Equatable, Sendable {
    public let sourceLabel: String
    public let titleLabel: String
    public let messageLabel: String?
    public let behaviorLabel: String
    public let queueLabel: String?
    public let openControl: CardAccessibilityControl?
    public let closeControl: CardAccessibilityControl?
    public let arrivalAnnouncement: String
    public let orderedElements: [CardAccessibilityElement]

    public init(content: NotificationCardContent) {
        sourceLabel = content.sourceName
        titleLabel = content.title
        messageLabel = content.message.isEmpty ? nil : content.message
        behaviorLabel = CardAccessibilityCopy.behavior(for: content.presentation)
        queueLabel = CardAccessibilityCopy.queueStatus(content.queueContext)
        openControl = content.hasOpenAction ? .init(
            label: CardAccessibilityCopy.openLabel,
            hint: CardAccessibilityCopy.openHint,
            identifier: NotificationCardAccessibilityIdentifier.open.rawValue
        ) : nil
        closeControl = content.canDismiss ? .init(
            label: CardAccessibilityCopy.closeLabel,
            hint: CardAccessibilityCopy.closeHint,
            identifier: NotificationCardAccessibilityIdentifier.close.rawValue
        ) : nil
        arrivalAnnouncement = CardAccessibilityCopy.arrival(for: content)

        var elements: [CardAccessibilityElement] = [
            .init(
                role: .secondaryContext,
                label: content.sourceName,
                value: CardAccessibilityCopy.sourceValue,
                identifier: NotificationCardAccessibilityIdentifier.source.rawValue
            ),
            .init(
                role: .summary,
                label: behaviorLabel,
                identifier: NotificationCardAccessibilityIdentifier.behavior.rawValue
            )
        ]
        if !content.title.isEmpty {
            elements.append(.init(
                role: .heading,
                label: content.title,
                identifier: NotificationCardAccessibilityIdentifier.title.rawValue
            ))
        }
        if let messageLabel {
            elements.append(.init(
                role: .staticText,
                label: messageLabel,
                identifier: NotificationCardAccessibilityIdentifier.message.rawValue
            ))
        }
        if let queueLabel {
            elements.append(.init(
                role: .status,
                label: queueLabel,
                identifier: NotificationCardAccessibilityIdentifier.queue.rawValue
            ))
        }
        if let openControl {
            elements.append(.init(
                role: .button,
                label: openControl.label,
                hint: openControl.hint,
                identifier: openControl.identifier
            ))
        }
        if let closeControl {
            elements.append(.init(
                role: .button,
                label: closeControl.label,
                hint: closeControl.hint,
                identifier: closeControl.identifier
            ))
        }
        orderedElements = elements
    }
}

/// Centralized English copy keeps the semantic builder localization-ready without tying
/// DockCatCore to Bundle or AppKit localization APIs.
public enum CardAccessibilityCopy {
    public static let sourceValue = "Notification source."
    public static let openLabel = "Open notification"
    public static let openHint = "Opens the associated secure link and dismisses the DockCat card."
    public static let closeLabel = "Dismiss notification"
    public static let closeHint = "Dismisses the DockCat card."
    public static let updatedAnnouncement = "DockCat notification updated."

    public static func behavior(for presentation: CardPresentationKind) -> String {
        switch presentation {
        case .persistent:
            return "Persistent. Remains until dismissed or removed by its source."
        case .transient:
            return "Transient. Closes automatically."
        }
    }

    public static func queueStatus(_ context: CardQueueContext) -> String? {
        let waiting: String?
        switch context.pendingCount {
        case 0: waiting = nil
        case 1: waiting = "One additional notification waiting."
        default: waiting = "\(context.pendingCount) additional notifications waiting."
        }
        if context.isDeliveryPaused {
            return [waiting, "Delivery paused."].compactMap { $0 }.joined(separator: " ")
        }
        return waiting
    }

    public static func arrival(for content: NotificationCardContent) -> String {
        let source = content.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = [source.isEmpty
            ? "DockCat notification."
            : "DockCat notification from \(source)."]
        parts.append(content.presentation == .persistent ? "Persistent." : "Transient.")
        switch content.queueContext.pendingCount {
        case 0: break
        case 1: parts.append("One more notification waiting.")
        default: parts.append("\(content.queueContext.pendingCount) more notifications waiting.")
        }
        if content.queueContext.isDeliveryPaused { parts.append("Delivery paused.") }
        return parts.joined(separator: " ")
    }
}
