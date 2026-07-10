import DockCatCore

struct DeveloperNotificationSource: NotificationSource {
    let sourceIdentifier = "developer"
    func start(handler: @escaping @Sendable (DockCatNotification) async -> Void) async {}
    func stop() async {}
}
