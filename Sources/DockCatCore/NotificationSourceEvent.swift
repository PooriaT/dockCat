public enum NotificationSourceEvent: Sendable, Equatable {
    case notification(DockCatNotification)
    case accessibilitySnapshot(AccessibilityNotificationSnapshot)
}
