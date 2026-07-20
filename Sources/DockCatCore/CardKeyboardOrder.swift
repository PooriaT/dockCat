import Foundation

public enum CardKeyboardTarget: String, Equatable, Sendable {
    case open
    case close
    case message

    public init(_ target: CardInitialFocusTarget) {
        switch target {
        case .open: self = .open
        case .close: self = .close
        case .message: self = .message
        }
    }
}

public enum CardKeyboardOrder {
    public static func forward(
        isInteractive: Bool,
        hasOpenAction: Bool,
        canDismiss: Bool,
        bodySupportsKeyboardScrolling: Bool
    ) -> [CardKeyboardTarget] {
        guard isInteractive else { return [] }
        var result: [CardKeyboardTarget] = []
        if hasOpenAction { result.append(.open) }
        if canDismiss { result.append(.close) }
        if bodySupportsKeyboardScrolling { result.append(.message) }
        return result
    }

    public static func reverse(
        isInteractive: Bool,
        hasOpenAction: Bool,
        canDismiss: Bool,
        bodySupportsKeyboardScrolling: Bool
    ) -> [CardKeyboardTarget] {
        Array(forward(
            isInteractive: isInteractive,
            hasOpenAction: hasOpenAction,
            canDismiss: canDismiss,
            bodySupportsKeyboardScrolling: bodySupportsKeyboardScrolling
        ).reversed())
    }
}
