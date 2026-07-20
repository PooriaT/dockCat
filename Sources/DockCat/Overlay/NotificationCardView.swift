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
    }

    let content: NotificationCardContent
    let actionURL: URL?
    let cardWidth: CGFloat
    let layoutPlan: CardContentLayoutPlan
    let interactionFocusGeneration: UInt64?
    let measurementsChanged: (CardContentRegionMeasurements) -> Void
    let requestInteraction: (CardInteractionTrigger) -> Void
    let closeRequested: () -> Void
    let openRequested: (URL) -> Void

    @FocusState private var focusedControl: FocusedControl?

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(CardContentLayoutMetrics.standard.interSectionSpacing)) {
            header

            if !content.title.isEmpty {
                Text(content.title)
                    .font(.headline)
                    .lineLimit(layoutPlan.titleLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                    .reportCardHeight(.title)
            }

            if !content.message.isEmpty {
                messageRegion
            }

            if content.hasOpenAction, let actionURL {
                Button("Open") {
                    openRequested(actionURL)
                }
                .focused($focusedControl, equals: .open)
                .accessibilityIdentifier("dockcat.card.open")
                .accessibilityHint("Opens the notification link in your browser")
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(3)
                .reportCardHeight(.actions)
            }

            if let queueText = content.queueContext.visibleText {
                Label(queueText, systemImage: "tray.full")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, CGFloat(
                        CardContentLayoutMetrics.standard.queueFooterSpacing
                        - CardContentLayoutMetrics.standard.interSectionSpacing
                    ))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(3)
                    .reportCardHeight(.queueFooter)
            }
        }
        .padding(.horizontal, CGFloat(CardContentLayoutMetrics.standard.horizontalPadding))
        .padding(.vertical, CGFloat(CardContentLayoutMetrics.standard.verticalPadding))
        .frame(
            width: cardWidth,
            height: CGFloat(layoutPlan.cardSize.height),
            alignment: .topLeading
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dockcat.card")
        .accessibilityLabel("DockCat notification from \(content.sourceName)")
        .accessibilityAction(named: "Interact with notification") {
            requestInteraction(.accessibility)
        }
        .onAppear { applyInitialFocusIfRequested() }
        .onChange(of: interactionFocusGeneration) {
            applyInitialFocusIfRequested()
        }
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

    private var header: some View {
        HStack {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(.orange)
            Text(content.sourceName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if content.canDismiss {
                Button(action: closeRequested) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .focused($focusedControl, equals: .close)
                .accessibilityIdentifier("dockcat.card.close")
                .accessibilityLabel("Dismiss notification")
            }
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
            .reportCardHeight(.body)
    }

    private func applyInitialFocusIfRequested() {
        guard interactionFocusGeneration != nil else {
            focusedControl = nil
            return
        }
        switch CardInitialFocusTarget.resolve(
            hasOpenAction: content.hasOpenAction,
            canDismiss: content.canDismiss,
            bodySupportsKeyboardScrolling: false
        ) {
        case .open: focusedControl = .open
        case .close: focusedControl = .close
        case .message, nil: focusedControl = nil
        }
    }
}
