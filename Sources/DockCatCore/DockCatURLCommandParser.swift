import Foundation

public struct DockCatURLCommandParser: Sendable {
    public var defaultDuration: TimeInterval

    public init(defaultDuration: TimeInterval = 5) {
        self.defaultDuration = defaultDuration
    }

    public func parse(_ url: URL) throws -> DockCatURLCommand {
        guard url.scheme?.lowercased() == "dockcat" else {
            throw DockCatURLCommandParseError.unsupportedScheme
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let host = components.host?.lowercased() else {
            throw DockCatURLCommandParseError.malformedURL
        }

        switch host {
        case "notify":
            do {
                return .notify(try URLSchemeParser(defaultDuration: defaultDuration).parse(url))
            } catch let error as URLSchemeParser.ParseError {
                switch error {
                case .unsupportedScheme: throw DockCatURLCommandParseError.unsupportedScheme
                case .malformed: throw DockCatURLCommandParseError.malformedURL
                case .unknownQueryKey: throw DockCatURLCommandParseError.unknownQueryKey
                case .duplicateQueryKey: throw DockCatURLCommandParseError.duplicateQueryKey
                case .missingTitle, .invalidDuration, .valueTooLong, .unsafeActionURL:
                    throw DockCatURLCommandParseError.invalidNotification
                }
            } catch {
                throw DockCatURLCommandParseError.invalidNotification
            }

        case "settings":
            let items = try normalizedQueryItems(components.queryItems ?? [], allowed: ["restoremenubar"])
            guard let rawValue = items["restoremenubar"] else {
                return .openSettings(restoreMenuBar: false)
            }
            return .openSettings(restoreMenuBar: try parseBoolean(rawValue))

        case "restore-menu-bar":
            _ = try normalizedQueryItems(components.queryItems ?? [], allowed: [])
            return .restoreMenuBar

        default:
            throw DockCatURLCommandParseError.unsupportedCommand
        }
    }

    private func normalizedQueryItems(
        _ queryItems: [URLQueryItem],
        allowed: Set<String>
    ) throws -> [String: String] {
        var result: [String: String] = [:]
        for item in queryItems {
            let key = item.name.lowercased()
            guard allowed.contains(key) else {
                throw DockCatURLCommandParseError.unknownQueryKey
            }
            guard result[key] == nil else {
                throw DockCatURLCommandParseError.duplicateQueryKey
            }
            result[key] = item.value ?? ""
        }
        return result
    }

    private func parseBoolean(_ rawValue: String) throws -> Bool {
        switch rawValue.lowercased() {
        case "1", "true": true
        case "0", "false": false
        default: throw DockCatURLCommandParseError.invalidBoolean
        }
    }
}
