import Foundation

public struct AccessibilityDisplayOptions: Equatable, Sendable {
    public let reduceMotion: Bool
    public let increaseContrast: Bool
    public let reduceTransparency: Bool
    public let differentiateWithoutColor: Bool

    public init(
        reduceMotion: Bool,
        increaseContrast: Bool,
        reduceTransparency: Bool,
        differentiateWithoutColor: Bool
    ) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
        self.reduceTransparency = reduceTransparency
        self.differentiateWithoutColor = differentiateWithoutColor
    }

    public static let standard = AccessibilityDisplayOptions(
        reduceMotion: false,
        increaseContrast: false,
        reduceTransparency: false,
        differentiateWithoutColor: false
    )
}

public enum CardAppearanceCategory: String, Equatable, Sendable {
    case light
    case dark
}

public enum CardAccessibilityBackgroundStyle: String, Equatable, Sendable {
    case material
    case opaqueSystem
}

public enum CardAccessibilityBorderEmphasis: String, Equatable, Sendable {
    case standard
    case increased
}

public enum CardAccessibilityFocusEmphasis: String, Equatable, Sendable {
    case standard
    case increased
}

public struct CardAccessibilityAppearance: Equatable, Sendable {
    public let backgroundStyle: CardAccessibilityBackgroundStyle
    public let borderEmphasis: CardAccessibilityBorderEmphasis
    public let borderWidth: Double
    public let usesShadow: Bool
    public let showsDivider: Bool
    public let focusEmphasis: CardAccessibilityFocusEmphasis
    public let statusUsesTextAndSymbol: Bool
    public let category: String
}

public enum CardAccessibilityAppearancePolicy {
    public static func resolve(
        options: AccessibilityDisplayOptions,
        appearance: CardAppearanceCategory,
        interactionMode: CardInteractionMode,
        presentation: CardPresentationKind
    ) -> CardAccessibilityAppearance {
        let highContrast = options.increaseContrast
        let isInteractive: Bool
        if case .interactive = interactionMode { isInteractive = true } else { isInteractive = false }
        let background: CardAccessibilityBackgroundStyle = options.reduceTransparency
            ? .opaqueSystem : .material
        return CardAccessibilityAppearance(
            backgroundStyle: background,
            borderEmphasis: highContrast ? .increased : .standard,
            borderWidth: highContrast ? 2 : 1,
            usesShadow: !highContrast,
            showsDivider: highContrast,
            focusEmphasis: highContrast || isInteractive ? .increased : .standard,
            // Every DockCat status always uses copy plus a symbol. Differentiate Without
            // Color therefore strengthens an already non-color-only contract.
            statusUsesTextAndSymbol: true,
            category: [
                appearance.rawValue,
                background.rawValue,
                highContrast ? "high-contrast" : "standard-contrast",
                options.differentiateWithoutColor ? "differentiate" : "color-allowed",
                presentation == .persistent ? "persistent" : "transient"
            ].joined(separator: ".")
        )
    }
}
