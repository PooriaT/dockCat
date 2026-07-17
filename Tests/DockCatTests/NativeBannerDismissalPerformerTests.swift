import ApplicationServices
import XCTest
@testable import DockCat

@MainActor final class NativeBannerDismissalPerformerTests: XCTestCase {
    func testSiblingCloseOutsideParsedSubtreeIsNeverPressed() {
        let api = DismissalAXFake()
        let root = DismissalElement(1), sibling = DismissalElement(2, identifier: "notification.first")
        let siblingClose = DismissalElement(3, role: "AXButton", identifier: "notification.close", press: true)
        let selected = DismissalElement(4, identifier: "notification.second")
        sibling.children = [siblingClose]; root.children = [sibling, selected]
        let registry = AccessibilityElementRegistry()
        let token = registry.register(root: root, processIdentifier: 1)
        let outcome = NativeBannerDismissalPerformer(registry: registry, client: api, trust: DismissalTrust()).perform(
            token: token.identifier, sourceBundleIdentifier: "org.example.source", notificationSubtreePath: [1],
            stableContainerIdentifier: "notification.second", excluded: [], ownBundleIdentifier: "org.example.dockcat")
        XCTAssertEqual(outcome, .unsupported)
        XCTAssertTrue(api.pressed.isEmpty)
    }

    func testSelectedReferenceChangingToReplyFailsRevalidation() {
        let api = DismissalAXFake()
        let root = DismissalElement(1, identifier: "notification.root")
        let close = DismissalElement(2, role: "AXButton", identifier: "notification.close", press: true)
        close.identifierAfterFirstRead = "notification.reply"
        root.children = [close]
        let registry = AccessibilityElementRegistry()
        let token = registry.register(root: root, processIdentifier: 1)
        let outcome = NativeBannerDismissalPerformer(registry: registry, client: api, trust: DismissalTrust()).perform(
            token: token.identifier, sourceBundleIdentifier: "org.example.source", notificationSubtreePath: [],
            stableContainerIdentifier: "notification.root", excluded: [], ownBundleIdentifier: "org.example.dockcat")
        XCTAssertEqual(outcome, .rejected)
        XCTAssertTrue(api.pressed.isEmpty)
    }
}

@MainActor private final class DismissalTrust: AccessibilityTrustChecking {
    func isTrusted() -> Bool { true }
    func requestTrust() -> Bool { true }
}

@MainActor private final class DismissalElement: AccessibilityElementReference {
    let traversalIdentifier: Int
    let role: String?
    let identifier: String?
    let press: Bool
    var identifierAfterFirstRead: String?
    var identifierReads = 0
    var children: [DismissalElement] = []
    init(_ id: Int, role: String? = "AXGroup", identifier: String? = nil, press: Bool = false) {
        traversalIdentifier = id; self.role = role; self.identifier = identifier; self.press = press
    }
}

@MainActor private final class DismissalAXFake: AccessibilityAPIClientProtocol {
    var pressed: [Int] = []
    func application(processIdentifier: pid_t) -> any AccessibilityElementReference { DismissalElement(Int(processIdentifier)) }
    func makeObserver(processIdentifier: pid_t, callback: @escaping (any AccessibilityElementReference, String) -> Void) throws -> any AccessibilityObserverReference { throw AccessibilityClientError.unsupported }
    func attach(_ observer: any AccessibilityObserverReference) {}
    func detach(_ observer: any AccessibilityObserverReference) {}
    func add(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) throws {}
    func remove(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) {}
    func string(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> String? {
        let element = element as! DismissalElement
        if attribute == .role { return element.role }
        if attribute == .identifier {
            defer { element.identifierReads += 1 }
            return element.identifierReads > 0 ? (element.identifierAfterFirstRead ?? element.identifier) : element.identifier
        }
        return nil
    }
    func boolean(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> Bool? { nil }
    func elements(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> [any AccessibilityElementReference] { (element as! DismissalElement).children }
    func element(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> (any AccessibilityElementReference)? { nil }
    func actions(of element: any AccessibilityElementReference) throws -> [String] { (element as! DismissalElement).press ? [kAXPressAction as String] : [] }
    func press(_ element: any AccessibilityElementReference) throws { pressed.append(element.traversalIdentifier) }
}
