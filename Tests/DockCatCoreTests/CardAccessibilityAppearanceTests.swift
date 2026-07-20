import Testing
@testable import DockCatCore

struct CardAccessibilityAppearanceTests {
    @Test func transparencyAndContrastResolveIndependently() {
        let standard = CardAccessibilityAppearancePolicy.resolve(
            options: .standard, appearance: .light,
            interactionMode: .passive, presentation: .transient
        )
        #expect(standard.backgroundStyle == .material)
        #expect(standard.borderWidth == 1)

        let accessible = CardAccessibilityAppearancePolicy.resolve(
            options: .init(
                reduceMotion: false, increaseContrast: true,
                reduceTransparency: true, differentiateWithoutColor: true
            ),
            appearance: .dark, interactionMode: .passive, presentation: .persistent
        )
        #expect(accessible.backgroundStyle == .opaqueSystem)
        #expect(accessible.borderEmphasis == .increased)
        #expect(accessible.borderWidth == 2)
        #expect(accessible.focusEmphasis == .increased)
        #expect(accessible.statusUsesTextAndSymbol)
        #expect(accessible.category.contains("dark"))
    }

    @Test func keyboardOrderIsNativeAndPredictable() {
        #expect(CardKeyboardOrder.forward(
            isInteractive: false, hasOpenAction: true, canDismiss: true,
            bodySupportsKeyboardScrolling: true
        ).isEmpty)
        #expect(CardKeyboardOrder.forward(
            isInteractive: true, hasOpenAction: true, canDismiss: true,
            bodySupportsKeyboardScrolling: true
        ) == [.open, .close, .message])
        #expect(CardKeyboardOrder.forward(
            isInteractive: true, hasOpenAction: false, canDismiss: true,
            bodySupportsKeyboardScrolling: false
        ) == [.close])
        #expect(CardKeyboardOrder.reverse(
            isInteractive: true, hasOpenAction: true, canDismiss: true,
            bodySupportsKeyboardScrolling: true
        ) == [.message, .close, .open])
    }
}
