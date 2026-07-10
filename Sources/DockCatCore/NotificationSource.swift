import Foundation

public protocol NotificationSource: Sendable {
    var sourceIdentifier: String { get }
    func start(handler: @escaping @Sendable (DockCatNotification) async -> Void) async
    func stop() async
}
