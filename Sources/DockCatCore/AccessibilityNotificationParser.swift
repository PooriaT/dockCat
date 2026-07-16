import Foundation

public struct AccessibilityNotificationParser: Sendable {
    public struct Limits: Sendable, Equatable {
        public var fieldLength: Int
        public var actionCount: Int
        public init(fieldLength: Int = 512, actionCount: Int = 8) {
            self.fieldLength = max(1, fieldLength); self.actionCount = max(0, actionCount)
        }
    }

    public let limits: Limits
    public init(limits: Limits = .init()) { self.limits = limits }

    public func parse(_ snapshot: AccessibilityNotificationSnapshot) -> Result<AccessibilityNotificationCandidate, AccessibilityNotificationRejection> {
        let flattened = flatten(snapshot.root)
        let structuralTokens = flattened.flatMap { [$0.node.role, $0.node.subrole, $0.node.identifier].compactMap(normalizedToken) }
        let hasNotificationIdentity = structuralTokens.contains { token in
            token.contains("notification") || token.contains("banner") || token.contains("alert")
        }
        let hasWidgetIdentity = structuralTokens.contains { $0.contains("widget") } && !hasNotificationIdentity
        guard hasNotificationIdentity, !hasWidgetIdentity else { return .failure(.unrelatedStructure) }

        let kind: AccessibilityNotificationCandidate.StructuralKind = structuralTokens.contains(where: { $0.contains("banner") }) ? .banner
            : structuralTokens.contains(where: { $0.contains("alert") }) ? .alert : .unknown
        let source = field(in: flattened, identifiers: ["appname", "source", "application"])
        let title = field(in: flattened, identifiers: ["title", "header"])
        var message = field(in: flattened, identifiers: ["message", "body", "subtitle", "content"])
        let isRedacted = structuralTokens.contains { $0.contains("redacted") || $0.contains("hiddenpreview") || $0.contains("privacyplaceholder") }
        if isRedacted, message == .missing { message = .value("Preview hidden") }

        guard source.displayValue != nil || title.displayValue != nil || message.displayValue != nil else {
            return .failure(isRedacted ? .hiddenWithoutNotificationStructure : .insufficientVisibleContent)
        }

        let actions = flattened.compactMap { item -> AccessibilityNotificationCandidate.ActionDescriptor? in
            let role = normalizedToken(item.node.role) ?? ""
            guard role.contains("button") || !item.node.supportedActions.isEmpty else { return nil }
            return .init(identifier: bounded(item.node.identifier), label: visible(item.node.title).displayValue,
                         supportedActions: Array(item.node.supportedActions.prefix(8)).compactMap(bounded))
        }
        let stableID = flattened.compactMap { node -> String? in
            guard let id = node.node.identifier, let token = normalizedToken(id), token.contains("notification") || token.contains("banner") else { return nil }
            return bounded(id)
        }.first
        // Ignore leaf text/buttons: callbacks commonly add/remove those while the visible item is unchanged.
        let signature = flattened.compactMap { item -> String? in
            let role = normalizedToken(item.node.role) ?? ""
            guard !role.contains("statictext"), !role.contains("button") else { return nil }
            return "\(item.depth):\(role):\(normalizedToken(item.node.subrole) ?? "-")"
        }.prefix(16).joined(separator: "|")
        let lifecycle: AccessibilityNotificationCandidate.LifecycleHint
        switch snapshot.observationKind {
        case .created, .windowCreated: lifecycle = .appeared
        case .destroyed: lifecycle = .disappeared
        case .childrenChanged, .layoutChanged, .valueChanged: lifecycle = .changed
        case .unknown: lifecycle = .unknown
        }
        return .success(.init(sourceBundleIdentifier: snapshot.origin.bundleIdentifier,
                              sourceDisplayName: source, title: title, message: message,
                              actions: Array(actions.prefix(limits.actionCount)), structuralKind: kind,
                              lifecycleHint: lifecycle,
                              capture: .init(sequence: snapshot.captureSequence, processIdentifier: snapshot.origin.processIdentifier,
                                             stableContainerIdentifier: stableID, coarseStructuralSignature: signature,
                                             traversalWasTruncated: snapshot.traversalWasTruncated),
                              opaqueDismissalTokenIdentifier: bounded(snapshot.opaqueDismissalTokenIdentifier)))
    }

    private func flatten(_ root: AccessibilityNotificationSnapshot.Node) -> [(node: AccessibilityNotificationSnapshot.Node, depth: Int)] {
        var result: [(AccessibilityNotificationSnapshot.Node, Int)] = []
        func visit(_ node: AccessibilityNotificationSnapshot.Node, _ depth: Int) {
            result.append((node, depth)); node.children.forEach { visit($0, depth + 1) }
        }
        visit(root, 0); return result
    }
    private func field(in nodes: [(node: AccessibilityNotificationSnapshot.Node, depth: Int)], identifiers: [String]) -> AccessibilityNotificationCandidate.VisibleField {
        for item in nodes {
            let token = normalizedToken(item.node.identifier) ?? ""
            guard identifiers.contains(where: token.contains) else { continue }
            if item.node.value != nil { return visible(item.node.value) }
            if item.node.title != nil { return visible(item.node.title) }
        }
        return .missing
    }
    private func visible(_ value: String?) -> AccessibilityNotificationCandidate.VisibleField {
        guard let value else { return .missing }
        let normalized = value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !normalized.isEmpty else { return .empty }
        return .value(String(normalized.prefix(limits.fieldLength)))
    }
    private func bounded(_ value: String?) -> String? { value.map { String($0.prefix(limits.fieldLength)) } }
    private func normalizedToken(_ value: String?) -> String? {
        value?.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

public struct AccessibilityNotificationExclusionPolicy: Sendable {
    public let ownBundleIdentifier: String
    public var internalIdentifiers: Set<String>
    public init(ownBundleIdentifier: String, internalIdentifiers: Set<String> = ["dockcat.overlay", "dockcat.simulator", "dockcat.url-scheme"]) {
        self.ownBundleIdentifier = ownBundleIdentifier; self.internalIdentifiers = internalIdentifiers
    }
    public func rejection(for candidate: AccessibilityNotificationCandidate) -> AccessibilityNotificationRejection? {
        if candidate.sourceBundleIdentifier == ownBundleIdentifier { return .excludedOrigin }
        let id = candidate.capture.stableContainerIdentifier?.lowercased()
        if let id, internalIdentifiers.contains(where: id.contains) { return .excludedInternalStructure }
        return nil
    }
}
