import Foundation

public struct AccessibilityNotificationSnapshot: Sendable, Equatable {
    public enum ObservationKind: String, Sendable, Codable { case created, childrenChanged, layoutChanged, windowCreated, valueChanged, destroyed, unknown }
    public struct Origin: Sendable, Equatable { public let bundleIdentifier: String?; public let processIdentifier: Int32 }
    public struct Node: Sendable, Equatable {
        public let role, subrole, identifier, title, value, elementDescription, help: String?
        public let enabled, selected: Bool?
        public let supportedActions: [String]
        public let children: [Node]
        public init(role: String? = nil, subrole: String? = nil, identifier: String? = nil, title: String? = nil,
                    value: String? = nil, elementDescription: String? = nil, help: String? = nil,
                    enabled: Bool? = nil, selected: Bool? = nil, supportedActions: [String] = [], children: [Node] = []) {
            self.role = role; self.subrole = subrole; self.identifier = identifier; self.title = title
            self.value = value; self.elementDescription = elementDescription; self.help = help
            self.enabled = enabled; self.selected = selected; self.supportedActions = supportedActions; self.children = children
        }
    }
    public let origin: Origin
    public let observationKind: ObservationKind
    public let captureSequence: UInt64
    public let root: Node
    public let opaqueDismissalTokenIdentifier: String?
    public let traversalWasTruncated: Bool
    public init(origin: Origin, observationKind: ObservationKind, captureSequence: UInt64, root: Node,
                opaqueDismissalTokenIdentifier: String? = nil, traversalWasTruncated: Bool = false) {
        self.origin = origin; self.observationKind = observationKind; self.captureSequence = captureSequence
        self.root = root; self.opaqueDismissalTokenIdentifier = opaqueDismissalTokenIdentifier
        self.traversalWasTruncated = traversalWasTruncated
    }
}
