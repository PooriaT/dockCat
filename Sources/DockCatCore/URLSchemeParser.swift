import Foundation

public struct URLSchemeParser: Sendable {
    public enum ParseError: Error, Equatable {
        case unsupportedScheme
        case malformed
        case unknownQueryKey
        case duplicateQueryKey
        case missingTitle
        case invalidDuration
        case valueTooLong
        case unsafeActionURL
    }

    private static let allowedQueryKeys = Set([
        "title", "message", "source", "type", "duration", "action"
    ])

    public var defaultDuration: TimeInterval
    public init(defaultDuration: TimeInterval = 5) { self.defaultDuration = defaultDuration }

    public func parse(_ url: URL) throws -> DockCatNotification {
        guard url.scheme?.lowercased() == "dockcat", url.host?.lowercased() == "notify" else { throw ParseError.unsupportedScheme }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.fragment == nil, parts.path.isEmpty || parts.path == "/" else {
            throw ParseError.malformed
        }
        var items: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            let key = item.name.lowercased()
            guard Self.allowedQueryKeys.contains(key) else { throw ParseError.unknownQueryKey }
            guard items[key] == nil else { throw ParseError.duplicateQueryKey }
            items[key] = item.value ?? ""
        }
        func checked(_ key: String, max: Int) throws -> String? {
            guard let value = items[key], !value.isEmpty else { return nil }
            guard value.count <= max else { throw ParseError.valueTooLong }
            return value
        }
        guard let title = try checked("title", max: 120) else { throw ParseError.missingTitle }
        let message = try checked("message", max: 1_000) ?? ""
        let source = try checked("source", max: 80) ?? "DockCat"
        let presentation: DockCatNotification.Presentation
        if items["type"]?.lowercased() == "persistent" { presentation = .persistent }
        else {
            let duration: TimeInterval
            if let raw = items["duration"] {
                guard let parsed = Double(raw), (1...60).contains(parsed) else { throw ParseError.invalidDuration }
                duration = parsed
            } else { duration = min(60, max(1, defaultDuration)) }
            presentation = .transient(duration: duration)
        }
        var action: URL?
        if let raw = try checked("action", max: 2_048) {
            guard let candidate = URL(string: raw),
                  candidate.scheme?.lowercased() == "https",
                  candidate.host?.isEmpty == false else {
                throw ParseError.unsafeActionURL
            }
            action = candidate
        }
        return DockCatNotification(sourceName: source, title: title, message: message, presentation: presentation, actionURL: action)
    }
}
