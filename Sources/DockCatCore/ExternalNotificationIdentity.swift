import Foundation

/// Privacy-safe identity supplied by an external notification source.
/// The namespace prevents identifiers from different sources from colliding.
public struct ExternalNotificationIdentity: Hashable, Sendable, Codable {
    public let sourceNamespace: String
    public let stableItemIdentifier: String

    public init(sourceNamespace: String, stableItemIdentifier: String) {
        self.sourceNamespace = sourceNamespace
        self.stableItemIdentifier = stableItemIdentifier
    }
}

public struct ExternalNotification: Equatable, Sendable {
    public let identity: ExternalNotificationIdentity
    public let notification: DockCatNotification

    public init(identity: ExternalNotificationIdentity, notification: DockCatNotification) {
        self.identity = identity
        self.notification = notification
    }
}
