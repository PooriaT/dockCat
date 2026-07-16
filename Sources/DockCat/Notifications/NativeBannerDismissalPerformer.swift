import ApplicationServices
import DockCatCore
import Foundation
import OSLog

@MainActor final class NativeBannerDismissalPerformer {
    enum Outcome: Equatable { case pressed, tokenMissingOrExpired, excluded, permissionRequired, unsupported, ambiguous, rejected, pressFailed }
    private let registry: AccessibilityElementRegistry
    private let client: AccessibilityAPIClientProtocol
    private let trust: AccessibilityTrustChecking
    private let policy = CloseControlSelectionPolicy()
    private let logger = Logger(subsystem: "com.example.DockCat", category: "NativeBannerDismissal")

    init(registry: AccessibilityElementRegistry, client: AccessibilityAPIClientProtocol,
         trust: AccessibilityTrustChecking = AccessibilityTrustController()) {
        self.registry = registry; self.client = client; self.trust = trust
    }

    func perform(token identifier: String, sourceBundleIdentifier: String?, excluded: Set<String>, ownBundleIdentifier: String) -> Outcome {
        guard trust.isTrusted() else { registry.removeAll(); logger.error("AX press stopped: permission required"); return .permissionRequired }
        let source = DockCatPreferences.normalizeBundleIdentifier(sourceBundleIdentifier ?? "")
        guard !source.isEmpty, source != DockCatPreferences.normalizeBundleIdentifier(ownBundleIdentifier), !excluded.contains(source) else {
            logger.info("Dismissal exclusion matched bundle identifier"); registry.invalidate(identifier); return .excluded
        }
        guard let entry = registry.resolve(identifier) else { logger.info("Dismissal token missing or expired"); return .tokenMissingOrExpired }
        var descriptors: [CloseControlDescriptor] = []
        func visit(_ element: any AccessibilityElementReference, path: [Int], depth: Int) {
            guard depth <= 6 else { return }
            let actions = (try? client.actions(of: element)) ?? []
            descriptors.append(.init(path: path, role: try? client.string(.role, of: element),
                                     subrole: try? client.string(.subrole, of: element), identifier: try? client.string(.identifier, of: element),
                                     localizedLabel: nil, supportsPress: actions.contains(kAXPressAction as String), isDescendantOfNotification: true))
            for (index, child) in ((try? client.elements(.children, of: element)) ?? []).enumerated() { visit(child, path: path + [index], depth: depth + 1) }
        }
        visit(entry.root, path: [], depth: 0)
        switch policy.select(from: descriptors) {
        case .ambiguous: logger.info("Selector outcome ambiguous"); registry.invalidate(identifier); return .ambiguous
        case .unsupported: logger.info("Selector outcome unsupported"); registry.invalidate(identifier); return .unsupported
        case .rejected: logger.info("Selector outcome rejected"); registry.invalidate(identifier); return .rejected
        case .selected(let selected):
            var element = entry.root
            for index in selected.path {
                guard let children = try? client.elements(.children, of: element), children.indices.contains(index) else { registry.invalidate(identifier); return .unsupported }
                element = children[index]
            }
            guard ((try? client.actions(of: element)) ?? []).contains(kAXPressAction as String) else { registry.invalidate(identifier); return .unsupported }
            do { try client.press(element); registry.invalidate(identifier); logger.info("AX press success"); return .pressed }
            catch { registry.invalidate(identifier); logger.error("AX press typed error"); return .pressFailed }
        }
    }
}
