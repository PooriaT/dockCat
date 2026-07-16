import DockCatCore
import Foundation

struct AccessibilitySnapshotLimits: Sendable, Equatable {
    var maximumDepth = 6, maximumNodeCount = 80, maximumStringLength = 512, maximumTotalTextLength = 8_192
}

@MainActor final class AccessibilitySnapshotBuilder {
    struct Result { let snapshot: AccessibilityNotificationSnapshot; let truncatedNodeCount: Int }
    private let client: AccessibilityAPIClientProtocol
    let limits: AccessibilitySnapshotLimits
    init(client: AccessibilityAPIClientProtocol, limits: AccessibilitySnapshotLimits = .init()) { self.client = client; self.limits = limits }

    func build(from root: any AccessibilityElementReference, origin: AccessibilityNotificationSnapshot.Origin,
               kind: AccessibilityNotificationSnapshot.ObservationKind, sequence: UInt64,
               observedElementIdentifier: String? = nil) -> Result {
        var visited = Set<Int>(), nodes = 0, text = 0, truncations = 0
        func clipped(_ value: String?) -> String? {
            guard let value else { return nil }; let remaining = max(0, limits.maximumTotalTextLength - text)
            let allowed = min(limits.maximumStringLength, remaining); let result = String(value.prefix(allowed))
            if result.count < value.count { truncations += 1 }; text += result.count; return result
        }
        func node(_ element: any AccessibilityElementReference, depth: Int) -> AccessibilityNotificationSnapshot.Node? {
            let identity = element.traversalIdentifier
            guard !visited.contains(identity), nodes < limits.maximumNodeCount else { truncations += 1; return nil }
            visited.insert(identity); nodes += 1
            func string(_ a: AccessibilityAttribute) -> String? { clipped(try? client.string(a, of: element)) }
            let actions = ((try? client.actions(of: element)) ?? []).compactMap(clipped)
            var children: [AccessibilityNotificationSnapshot.Node] = []
            if depth < limits.maximumDepth { children = ((try? client.elements(.children, of: element)) ?? []).compactMap { node($0, depth: depth + 1) } }
            else if !((try? client.elements(.children, of: element)) ?? []).isEmpty { truncations += 1 }
            return .init(role: string(.role), subrole: string(.subrole), identifier: string(.identifier), title: string(.title),
                         value: string(.value), elementDescription: string(.elementDescription), help: string(.help),
                         enabled: try? client.boolean(.enabled, of: element), selected: try? client.boolean(.selected, of: element),
                         supportedActions: actions, children: children)
        }
        let built = node(root, depth: 0) ?? .init()
        let boundedObservedIdentifier = observedElementIdentifier.map { String($0.prefix(limits.maximumStringLength)) }
        return .init(snapshot: .init(origin: origin, observationKind: kind, captureSequence: sequence, root: built,
                                     observedElementIdentifier: boundedObservedIdentifier,
                                     traversalWasTruncated: truncations > 0), truncatedNodeCount: truncations)
    }
}
