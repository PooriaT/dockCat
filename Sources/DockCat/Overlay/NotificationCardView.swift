import AppKit
import DockCatCore
import SwiftUI

struct NotificationCardView: View {
    let notification: DockCatNotification
    let canDismiss: Bool
    let opensAction: Bool
    let cardWidth: CGFloat
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pawprint.fill").foregroundStyle(.orange)
                Text(notification.sourceName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if canDismiss { Button(action: dismiss) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Dismiss notification") }
            }
            Text(notification.title).font(.headline).lineLimit(2)
            Text(notification.message).font(.body).foregroundStyle(.secondary).lineLimit(4)
            if opensAction, let url = notification.actionURL {
                Button("Open") { NSWorkspace.shared.open(url); dismiss() }.accessibilityHint("Opens the notification link in your browser")
            }
        }
        .padding(16).frame(width: cardWidth).frame(minHeight: CardLayoutMetrics.minimumHeight, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2)))
        .accessibilityElement(children: .contain).accessibilityLabel("DockCat notification from \(notification.sourceName)")
    }
}
