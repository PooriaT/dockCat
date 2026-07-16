import XCTest
@testable import DockCatCore

final class ExternalPresentationPolicyTests: XCTestCase {
    private func candidate(kind: AccessibilityNotificationCandidate.StructuralKind, actions: [AccessibilityNotificationCandidate.ActionDescriptor] = []) -> AccessibilityNotificationCandidate {
        .init(sourceBundleIdentifier: "source", sourceDisplayName: .value("App"), title: .value("Title"), message: .value("Body"),
              actions: actions, structuralKind: kind, lifecycleHint: .unknown,
              capture: .init(sequence: 1, processIdentifier: 1, stableContainerIdentifier: "stable", coarseStructuralSignature: "sig", traversalWasTruncated: false),
              opaqueDismissalTokenIdentifier: nil)
    }
    func testDeterministicStructuralClassification() {
        let policy = ExternalPresentationPolicy()
        guard case .transient = policy.classify(candidate(kind: .banner)) else { return XCTFail() }
        let action = AccessibilityNotificationCandidate.ActionDescriptor(identifier: "reply", label: nil, supportedActions: ["press"])
        guard case .persistent = policy.classify(candidate(kind: .alert, actions: [action])) else { return XCTFail() }
        guard case .ambiguous = policy.classify(candidate(kind: .unknown)) else { return XCTFail() }
    }
}
