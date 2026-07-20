import DockCatCore
import Foundation
import SwiftUI

private enum CardSemanticRegion: Hashable {
    case header
    case title
    case body
    case actions
    case queueFooter
}

private struct CardRegionHeightPreference: PreferenceKey {
    static let defaultValue: [CardSemanticRegion: CGFloat] = [:]

    static func reduce(
        value: inout [CardSemanticRegion: CGFloat],
        nextValue: () -> [CardSemanticRegion: CGFloat]
    ) {
        for (region, height) in nextValue() {
            value[region] = max(value[region] ?? 0, height)
        }
    }
}

private extension View {
    func reportCardHeight(_ region: CardSemanticRegion) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: CardRegionHeightPreference.self,
                    value: [region: geometry.size.height]
                )
            }
        }
    }
}

struct NotificationCardView: View {
    private enum FocusedControl: Hashable {
        case open
        case close
        case message
    }

    let content: NotificationCardContent
    let accessibility: NotificationCardAccessibilityModel
    let accessibilityAppearance: CardAccessibilityAppearance
    let isInteractive: Bool
    let actionURL: URL?
    let cardWidth: CGFloat
    let layoutPlan: CardContentLayoutPlan
    let interactionFocusGeneration: UInt64?
    let preferredFocusTarget: CardKeyboardTarget?
    let measurementsChanged: (CardContentRegionMeasurements) -> Void
    let focusChanged: (CardKeyboardTarget?) -> Void
    let requestInteraction: (CardInteractionTrigger) -> Void
    let closeRequested: () -> Void
    let openRequested: (URL) -> Void

    @FocusState private var focusedControl: FocusedControl?

    var body: some View {
        measuredCard
    }

    private var interactiveCard: some View {
        surfacedCard
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(NotificationCardAccessibilityIdentifier.container.rawValue)
            .accessibilityAction(named: "Interact with notification") {
                requestInteraction(.accessibility)
            }
            .onKeyPress(keys: [.tab]) { press in
                moveKeyboardFocus(reverse: press.modifiers.contains(.shift))
            }
            .onAppear { applyInitialFocusIfRequested() }
            .onChange(of: interactionFocusGeneration) {
                applyInitialFocusIfRequested()
            }
            .onChange(of: focusedControl) {
                focusChanged(currentKeyboardTarget)
            }
    }

    private var measuredCard: some View {
        interactiveCard
            .onPreferenceChange(CardRegionHeightPreference.self) { heights in
                measurementsChanged(.init(
                    headerHeight: Double(heights[.header] ?? 0),
                    titleHeight: Double(heights[.title] ?? 0),
                    bodyHeight: Double(heights[.body] ?? 0),
                    actionsHeight: Double(heights[.actions] ?? 0),
                    queueFooterHeight: Double(heights[.queueFooter] ?? 0)
                ))
            }
    }

    private var surfacedCard: some View {
        cardLayout
            .background { cardBackground }
            .overlay { cardBorder }
    }

    private var cardLayout: some View {
        VStack(alignment: .leading, spacing: CGFloat(CardContentLayoutMetrics.standard.interSectionSpacing)) {
            header

            if !content.title.isEmpty {
                Text(content.title)
                    .font(.headline)
                    .lineLimit(layoutPlan.titleLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .accessibilityIdentifier(NotificationCardAccessibilityIdentifier.title.rawValue)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilitySortPriority(50)
                    .reportCardHeight(.title)
            }

            if !content.message.isEmpty {
                messageRegion
            }

            if let queueText = content.queueContext.visibleText,
               let queueLabel = accessibility.queueLabel {
                Label(queueText, systemImage: "tray.full")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, CGFloat(
                        CardContentLayoutMetrics.standard.queueFooterSpacing
                        - CardContentLayoutMetrics.standard.interSectionSpacing
                    ))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(3)
                    .accessibilityIdentifier(NotificationCardAccessibilityIdentifier.queue.rawValue)
                    .accessibilityLabel(queueLabel)
                    .accessibilitySortPriority(30)
                    .reportCardHeight(.queueFooter)
            }

            if content.hasOpenAction || content.canDismiss {
                actions
                    .overlay(alignment: .top) {
                        if accessibilityAppearance.showsDivider {
                            Divider().offset(y: -4)
                        }
                    }
                    .reportCardHeight(.actions)
            }
        }
        .padding(.horizontal, CGFloat(CardContentLayoutMetrics.standard.horizontalPadding))
        .padding(.vertical, CGFloat(CardContentLayoutMetrics.standard.verticalPadding))
        .frame(
            width: cardWidth,
            height: CGFloat(layoutPlan.cardSize.height),
            alignment: .topLeading
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier(NotificationCardAccessibilityIdentifier.source.rawValue)
                    .accessibilityValue(CardAccessibilityCopy.sourceValue)
                    .accessibilitySortPriority(70)
                Label(
                    content.presentation == .persistent ? "Persistent" : "Closes automatically",
                    systemImage: content.presentation == .persistent ? "pin.fill" : "clock"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(NotificationCardAccessibilityIdentifier.behavior.rawValue)
                .accessibilityLabel(accessibility.behaviorLabel)
                .accessibilitySortPriority(60)
            }
            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(3)
        .reportCardHeight(.header)
    }

    @ViewBuilder
    private var messageRegion: some View {
        if layoutPlan.bodyScrolls {
            ScrollView(.vertical) {
                messageText
            }
            .frame(height: CGFloat(layoutPlan.bodyViewportHeight))
            .focusable(isInteractive)
            .focused($focusedControl, equals: .message)
        } else {
            messageText
        }
    }

    private var messageText: some View {
        Text(content.message)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .accessibilityIdentifier(NotificationCardAccessibilityIdentifier.message.rawValue)
            .accessibilitySortPriority(40)
            .reportCardHeight(.body)
    }

    private var actions: some View {
        HStack {
            if let openControl = accessibility.openControl,
               content.hasOpenAction,
               let actionURL {
                Button("Open") { openRequested(actionURL) }
                    .focused($focusedControl, equals: .open)
                    .accessibilityIdentifier(openControl.identifier)
                    .accessibilityLabel(openControl.label)
                    .accessibilityHint(openControl.hint)
                    .accessibilitySortPriority(20)
            }
            Spacer()
            if let closeControl = accessibility.closeControl, content.canDismiss {
                Button(action: closeRequested) {
                    Label("Dismiss", systemImage: "xmark.circle.fill")
                }
                .focused($focusedControl, equals: .close)
                .accessibilityIdentifier(closeControl.identifier)
                .accessibilityLabel(closeControl.label)
                .accessibilityHint(closeControl.hint)
                .accessibilitySortPriority(10)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(accessibilityAppearance.focusEmphasis == .increased ? .regular : .small)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(3)
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        switch accessibilityAppearance.backgroundStyle {
        case .material:
            shape.fill(.regularMaterial)
        case .opaqueSystem:
            shape.fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16)
            .stroke(
                Color(nsColor: .separatorColor),
                lineWidth: CGFloat(accessibilityAppearance.borderWidth)
            )
    }

    private func applyInitialFocusIfRequested() {
        guard interactionFocusGeneration != nil else {
            focusedControl = nil
            return
        }
        let available = CardKeyboardOrder.forward(
            isInteractive: true,
            hasOpenAction: content.hasOpenAction,
            canDismiss: content.canDismiss,
            bodySupportsKeyboardScrolling: layoutPlan.bodyScrolls
        )
        let target = preferredFocusTarget.flatMap { available.contains($0) ? $0 : nil }
        switch target ?? CardInitialFocusTarget.resolve(
            hasOpenAction: content.hasOpenAction,
            canDismiss: content.canDismiss,
            bodySupportsKeyboardScrolling: layoutPlan.bodyScrolls
        ).map(CardKeyboardTarget.init) {
        case .open: focusedControl = .open
        case .close: focusedControl = .close
        case .message: focusedControl = .message
        case nil: focusedControl = nil
        }
    }

    private var currentKeyboardTarget: CardKeyboardTarget? {
        switch focusedControl {
        case .open: .open
        case .close: .close
        case .message: .message
        case nil: nil
        }
    }

    private func moveKeyboardFocus(reverse: Bool) -> KeyPress.Result {
        let order = CardKeyboardOrder.forward(
            isInteractive: isInteractive,
            hasOpenAction: content.hasOpenAction,
            canDismiss: content.canDismiss,
            bodySupportsKeyboardScrolling: layoutPlan.bodyScrolls
        )
        guard !order.isEmpty else { return .ignored }
        let current = currentKeyboardTarget
        let currentIndex = current.flatMap(order.firstIndex(of:))
        let nextIndex: Int
        if reverse {
            nextIndex = currentIndex.map { ($0 - 1 + order.count) % order.count }
                ?? order.count - 1
        } else {
            nextIndex = currentIndex.map { ($0 + 1) % order.count } ?? 0
        }
        switch order[nextIndex] {
        case .open: focusedControl = .open
        case .close: focusedControl = .close
        case .message: focusedControl = .message
        }
        return .handled
    }
}
