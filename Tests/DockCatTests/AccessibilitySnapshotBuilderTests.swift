import XCTest
@testable import DockCat

@MainActor final class AccessibilitySnapshotBuilderTests: XCTestCase {
    func testDepthNodeStringAndCycleBounds() {
        let client = AXFake(); let root = FakeElement(1), child = FakeElement(2), third = FakeElement(3)
        root.strings[.title] = String(repeating: "x", count: 20); root.children = [child, third]
        child.children = [root]; third.children = [FakeElement(4)]
        let builder = AccessibilitySnapshotBuilder(client: client, limits: .init(maximumDepth: 1, maximumNodeCount: 2, maximumStringLength: 5, maximumTotalTextLength: 5))
        let result = builder.build(from: root, origin: .init(bundleIdentifier: nil, processIdentifier: 1), kind: .created, sequence: 1)
        XCTAssertEqual(result.snapshot.root.title, "xxxxx")
        XCTAssertEqual(result.snapshot.root.children.count, 1)
        XCTAssertTrue(result.snapshot.traversalWasTruncated)
    }

    func testMissingAttributesRemainNil() {
        let result = AccessibilitySnapshotBuilder(client: AXFake()).build(from: FakeElement(1), origin: .init(bundleIdentifier: nil, processIdentifier: 1), kind: .unknown, sequence: 2)
        XCTAssertNil(result.snapshot.root.role); XCTAssertNil(result.snapshot.root.enabled)
    }

    func testObservedElementIdentifierIsPassedThroughAsBoundedData() {
        let result = AccessibilitySnapshotBuilder(client: AXFake(), limits: .init(maximumDepth: 1, maximumNodeCount: 2,
            maximumStringLength: 5, maximumTotalTextLength: 20)).build(
                from: FakeElement(1), origin: .init(bundleIdentifier: nil, processIdentifier: 1),
                kind: .created, sequence: 3, observedElementIdentifier: "notification.long")
        XCTAssertEqual(result.snapshot.observedElementIdentifier, "notif")
    }
}

@MainActor private final class FakeElement: AccessibilityElementReference {
    let traversalIdentifier: Int; var strings: [AccessibilityAttribute: String] = [:]; var booleans: [AccessibilityAttribute: Bool] = [:]
    var children: [FakeElement] = []; weak var parent: FakeElement?
    init(_ id: Int) { traversalIdentifier = id }
}
@MainActor private final class FakeObserver: AccessibilityObserverReference {}
@MainActor private final class AXFake: AccessibilityAPIClientProtocol {
    func application(processIdentifier: pid_t) -> any AccessibilityElementReference { FakeElement(Int(processIdentifier)) }
    func makeObserver(processIdentifier: pid_t, callback: @escaping (any AccessibilityElementReference, String) -> Void) throws -> any AccessibilityObserverReference { FakeObserver() }
    func attach(_ observer: any AccessibilityObserverReference) {}
    func detach(_ observer: any AccessibilityObserverReference) {}
    func add(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) throws {}
    func remove(notification: String, element: any AccessibilityElementReference, observer: any AccessibilityObserverReference) {}
    func string(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> String? { (element as! FakeElement).strings[attribute] }
    func boolean(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> Bool? { (element as! FakeElement).booleans[attribute] }
    func elements(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> [any AccessibilityElementReference] { (element as! FakeElement).children }
    func element(_ attribute: AccessibilityAttribute, of element: any AccessibilityElementReference) throws -> (any AccessibilityElementReference)? { (element as! FakeElement).parent }
    func actions(of element: any AccessibilityElementReference) throws -> [String] { [] }
}
