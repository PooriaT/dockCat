import DockCatCore

enum AXFixtures {
    static func banner(title: String? = "Orbit status", body: String? = "A synthetic task finished.",
                       source: String? = "Example Lab", bundle: String? = "org.example.lab",
                       sequence: UInt64 = 1, extraChildren: [AccessibilityNotificationSnapshot.Node] = []) -> AccessibilityNotificationSnapshot {
        var children: [AccessibilityNotificationSnapshot.Node] = []
        if let source { children.append(.init(role: "AXStaticText", identifier: "appName", value: source)) }
        if let title { children.append(.init(role: "AXStaticText", identifier: "title", value: title)) }
        if let body { children.append(.init(role: "AXStaticText", identifier: "message", value: body)) }
        children += extraChildren
        return .init(origin: .init(bundleIdentifier: bundle, processIdentifier: 42), observationKind: .created,
                     captureSequence: sequence,
                     root: .init(role: "AXGroup", subrole: "AXNotificationBanner", identifier: "notification.synthetic.1", children: children))
    }
    static let alert = banner(extraChildren: [
        .init(role: "AXButton", identifier: "primaryAction", title: "Fortfahren", supportedActions: ["AXPress"]),
        .init(role: "AXButton", identifier: "secondaryAction", title: "Schließen", supportedActions: ["AXPress"])
    ])
    static let hidden = AccessibilityNotificationSnapshot(
        origin: .init(bundleIdentifier: "org.example.private", processIdentifier: 43), observationKind: .created, captureSequence: 2,
        root: .init(role: "AXGroup", subrole: "AXNotificationBanner", identifier: "notification.redacted.privacyPlaceholder",
                    children: [.init(role: "AXStaticText", identifier: "appName", value: "Private Example")]))
    static let hiddenTitle = banner(title: nil, body: "Visible invented body", extraChildren: [
        .init(role: "AXStaticText", identifier: "title.hiddenPreview")
    ])
    static let hiddenBody = banner(title: "Visible invented title", body: nil, extraChildren: [
        .init(role: "AXStaticText", identifier: "message.hiddenPreview")
    ])
    static let widget = AccessibilityNotificationSnapshot(
        origin: .init(bundleIdentifier: "org.example.widgets", processIdentifier: 44), observationKind: .layoutChanged, captureSequence: 3,
        root: .init(role: "AXGroup", subrole: "AXWidget", identifier: "weather.widget",
                    children: [.init(role: "AXStaticText", identifier: "title", value: "Invented forecast")]))
    static let unknown = AccessibilityNotificationSnapshot(
        origin: .init(bundleIdentifier: "org.example.unknown", processIdentifier: 45), observationKind: .unknown, captureSequence: 4,
        root: .init(role: "AXNovelRole", subrole: "AXNovelSubrole", children: []))
}
