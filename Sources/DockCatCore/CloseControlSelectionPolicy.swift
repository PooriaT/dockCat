import Foundation

/// A synthetic, Foundation-only description. AX references never cross into DockCatCore.
public struct CloseControlDescriptor: Sendable, Equatable {
    public let path: [Int]
    public let role: String?
    public let subrole: String?
    public let identifier: String?
    public let localizedLabel: String?
    public let supportsPress: Bool
    public let isDescendantOfNotification: Bool

    public init(path: [Int], role: String?, subrole: String?, identifier: String?, localizedLabel: String? = nil,
                supportsPress: Bool, isDescendantOfNotification: Bool) {
        self.path = path; self.role = role; self.subrole = subrole; self.identifier = identifier
        self.localizedLabel = localizedLabel; self.supportsPress = supportsPress
        self.isDescendantOfNotification = isDescendantOfNotification
    }
}

public enum CloseControlSelectionDecision: Sendable, Equatable {
    case selected(CloseControlDescriptor)
    case ambiguous
    case unsupported
    case rejected
}

public struct CloseControlSelectionPolicy: Sendable {
    public init() {}

    public func select(from controls: [CloseControlDescriptor]) -> CloseControlSelectionDecision {
        let buttons = controls.filter { normalized($0.role).contains("button") }
        guard !buttons.isEmpty else { return .unsupported }
        let plausible = buttons.filter { control in
            guard control.supportsPress, control.isDescendantOfNotification else { return false }
            let identifier = normalized(control.identifier)
            let subrole = normalized(control.subrole)
            let combined = identifier + subrole
            let forbidden = ["reply", "open", "option", "action", "content", "destructive", "delete"]
            guard !forbidden.contains(where: combined.contains) else { return false }
            // A label is deliberately ignored as primary evidence. Require a stable AX
            // identifier or subrole expressing close/dismiss semantics.
            return identifier.contains("close") || identifier.contains("dismiss") ||
                subrole.contains("close") || subrole.contains("dismiss")
        }
        guard !plausible.isEmpty else { return .rejected }
        guard plausible.count == 1 else { return .ambiguous }
        return .selected(plausible[0])
    }

    private func normalized(_ value: String?) -> String {
        value?.lowercased().filter(\.isLetter) ?? ""
    }
}
