import Foundation

public enum ApplicationRecoveryCommand: Equatable, Sendable {
    case showSettings
    case restoreMenuBar
}

public enum ApplicationRecoveryCommandParseError: String, Error, Equatable, Sendable {
    case unsupportedArgument
}

public struct ApplicationRecoveryCommandParser: Sendable {
    public init() {}

    /// Parses arguments after the executable name. The surface is intentionally recovery-only.
    public func parse(_ arguments: [String]) throws -> [ApplicationRecoveryCommand] {
        try arguments.map { argument in
            switch argument {
            case "--show-settings": .showSettings
            case "--restore-menu-bar": .restoreMenuBar
            default: throw ApplicationRecoveryCommandParseError.unsupportedArgument
            }
        }
    }
}
