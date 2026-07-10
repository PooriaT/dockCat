import Foundation

public struct URLSchemeParser: Sendable {
    public enum ParseError: Error, Equatable { case unsupportedScheme, malformed, missingTitle, invalidDuration, valueTooLong, unsafeActionURL }
    public var defaultDuration: TimeInterval
    public init(defaultDuration: TimeInterval = 5) { self.defaultDuration = defaultDuration }

    public func parse(_ url: URL) throws -> DockCatNotification {
        guard url.scheme?.lowercased() == "dockcat", url.host?.lowercased() == "notify" else { throw ParseError.unsupportedScheme }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw ParseError.malformed }
        let items = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name.lowercased(), $0.value ?? "") })
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
            guard let candidate = URL(string: raw), candidate.scheme?.lowercased() == "https" else { throw ParseError.unsafeActionURL }
            action = candidate
        }
        return DockCatNotification(sourceName: source, title: title, message: message, presentation: presentation, actionURL: action)
    }
}
