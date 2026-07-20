import ApplicationServices
import DockCatCore
import Foundation
import OSLog

@MainActor final class NativeBannerDismissalPerformer: NativeBannerDismissalPerforming {
    enum Outcome: Equatable { case pressed, tokenMissingOrExpired, excluded, permissionRequired, unsupported, ambiguous, rejected, pressFailed }
    private let registry: AccessibilityElementRegistry
    private let client: AccessibilityAPIClientProtocol
    private let trust: AccessibilityTrustChecking
    private let policy = CloseControlSelectionPolicy()
    private let logger = Logger(subsystem: DockCatProductIdentity.osLogSubsystem, category: "NativeBannerDismissal")

    init(registry: AccessibilityElementRegistry, client: AccessibilityAPIClientProtocol,
         trust: AccessibilityTrustChecking = AccessibilityTrustController()) {
        self.registry = registry; self.client = client; self.trust = trust
    }

    func perform(token identifier: String, sourceBundleIdentifier: String?, notificationSubtreePath: [Int],
                 stableContainerIdentifier: String?, excluded: Set<String>, ownBundleIdentifier: String) -> Outcome {
        guard trust.isTrusted() else { registry.removeAll(); logger.error("AX press stopped: permission required"); return .permissionRequired }
        let source = DockCatPreferences.normalizeBundleIdentifier(sourceBundleIdentifier ?? "")
        guard !source.isEmpty, source != DockCatPreferences.normalizeBundleIdentifier(ownBundleIdentifier), !excluded.contains(source) else {
            logger.info("Dismissal exclusion matched bundle identifier"); registry.invalidate(identifier); return .excluded
        }
        guard let entry = registry.resolve(identifier) else { logger.info("Dismissal token missing or expired"); return .tokenMissingOrExpired }
        var notificationRoot = entry.root
        for index in notificationSubtreePath {
            guard let children = try? client.elements(.children, of: notificationRoot), children.indices.contains(index) else {
                registry.invalidate(identifier); return .unsupported
            }
            notificationRoot = children[index]
        }
        // A non-root parser selection must still identify the same live container.
        // This fails closed if siblings reordered after the bounded snapshot.
        if !notificationSubtreePath.isEmpty {
            guard let expected = stableContainerIdentifier,
                  (try? client.string(.identifier, of: notificationRoot)) == expected else {
                registry.invalidate(identifier); logger.info("Selector outcome unsupported"); return .unsupported
            }
        }
        var candidates: [(descriptor: CloseControlDescriptor, element: any AccessibilityElementReference)] = []
        func visit(_ element: any AccessibilityElementReference, path: [Int], depth: Int) {
            guard depth <= 6 else { return }
            let actions = (try? client.actions(of: element)) ?? []
            let descriptor = CloseControlDescriptor(path: path, role: try? client.string(.role, of: element),
                                                    subrole: try? client.string(.subrole, of: element), identifier: try? client.string(.identifier, of: element),
                                                    localizedLabel: nil, supportsPress: actions.contains(kAXPressAction as String), isDescendantOfNotification: true)
            candidates.append((descriptor, element))
            for (index, child) in ((try? client.elements(.children, of: element)) ?? []).enumerated() { visit(child, path: path + [index], depth: depth + 1) }
        }
        visit(notificationRoot, path: [], depth: 0)
        switch policy.select(from: candidates.map(\.descriptor)) {
        case .ambiguous: logger.info("Selector outcome ambiguous"); registry.invalidate(identifier); return .ambiguous
        case .unsupported: logger.info("Selector outcome unsupported"); registry.invalidate(identifier); return .unsupported
        case .rejected: logger.info("Selector outcome rejected"); registry.invalidate(identifier); return .rejected
        case .selected(let selected):
            guard let element = candidates.first(where: { $0.descriptor == selected })?.element else { registry.invalidate(identifier); return .unsupported }
            // Press the exact reference selected above, never a second path lookup.
            // Re-read its live semantics and run the same fail-closed policy again.
            let liveActions = (try? client.actions(of: element)) ?? []
            let live = CloseControlDescriptor(path: selected.path, role: try? client.string(.role, of: element),
                                              subrole: try? client.string(.subrole, of: element), identifier: try? client.string(.identifier, of: element),
                                              localizedLabel: nil, supportsPress: liveActions.contains(kAXPressAction as String), isDescendantOfNotification: true)
            guard policy.select(from: [live]) == .selected(live),
                  live.identifier == selected.identifier, live.subrole == selected.subrole else {
                registry.invalidate(identifier); logger.info("Selector outcome rejected"); return .rejected
            }
            do { try client.press(element); registry.invalidate(identifier); logger.info("AX press success"); return .pressed }
            catch { registry.invalidate(identifier); logger.error("AX press typed error"); return .pressFailed }
        }
    }
}
