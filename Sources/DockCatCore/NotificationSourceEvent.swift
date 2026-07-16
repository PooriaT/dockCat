public enum NotificationSourceEvent: Sendable, Equatable {
    case notification(DockCatNotification)
    case oneShot(DockCatNotification)
    case appeared(ExternalNotification)
    case updated(ExternalNotification)
    case disappeared(ExternalNotificationIdentity)
    case accessibilitySnapshot(AccessibilityNotificationSnapshot)
}
