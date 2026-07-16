import Foundation

public struct DockCatNotification: Identifiable, Equatable, Sendable {
    public typealias ExternalIdentity = ExternalNotificationIdentity
    public enum Classification: Equatable, Sendable { case confident(String), bestEffort(String) }
    public enum Presentation: Equatable, Sendable {
        case transient(duration: TimeInterval)
        case persistent
    }

    public let id: UUID
    public let sourceName: String
    public let title: String
    public let message: String
    public let presentation: Presentation
    public let actionURL: URL?
    public let createdAt: Date
    /// Opaque source identity for later lifecycle reconciliation; it contains no notification text.
    public let externalIdentity: ExternalIdentity?
    public let classification: Classification?

    public init(id: UUID = UUID(), sourceName: String, title: String, message: String,
                presentation: Presentation = .transient(duration: 5), actionURL: URL? = nil,
                createdAt: Date = Date(), externalIdentity: ExternalIdentity? = nil,
                classification: Classification? = nil) {
        self.id = id
        self.sourceName = sourceName
        self.title = title
        self.message = message
        self.presentation = presentation
        self.actionURL = actionURL
        self.createdAt = createdAt
        self.externalIdentity = externalIdentity
        self.classification = classification
    }
}
