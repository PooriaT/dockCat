import Foundation

public enum DockCatURLCommand: Equatable, Sendable {
    case notify(DockCatNotification)
    case openSettings(restoreMenuBar: Bool)
    case restoreMenuBar
}

/// Contains categories only. It deliberately carries no URL or query value so it is safe to log.
public enum DockCatURLCommandParseError: String, Error, Equatable, Sendable {
    case unsupportedScheme
    case unsupportedCommand
    case malformedURL
    case unknownQueryKey
    case duplicateQueryKey
    case invalidBoolean
    case invalidNotification
}
