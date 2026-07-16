import Foundation
import XCTest
@testable import DockCat

@MainActor final class AccessibilityElementRegistryTests: XCTestCase {
    func testCapacityIsStrictlyBounded() {
        let registry = AccessibilityElementRegistry(capacity: 2)
        let first = registry.register(root: RegistryElement(1), processIdentifier: 1)
        _ = registry.register(root: RegistryElement(2), processIdentifier: 1)
        _ = registry.register(root: RegistryElement(3), processIdentifier: 1)
        XCTAssertEqual(registry.count, 2)
        XCTAssertNil(registry.resolve(first.identifier))
    }

    func testInjectedClockExpiresAndUseCanInvalidateToken() {
        var date = Date(timeIntervalSince1970: 100)
        let registry = AccessibilityElementRegistry(capacity: 2, lifetime: 2, now: { date })
        let token = registry.register(root: RegistryElement(1), processIdentifier: 1)
        XCTAssertNotNil(registry.resolve(token.identifier))
        date.addTimeInterval(3)
        XCTAssertNil(registry.resolve(token.identifier))

        let second = registry.register(root: RegistryElement(2), processIdentifier: 1)
        registry.invalidate(second.identifier)
        XCTAssertNil(registry.resolve(second.identifier))
    }
}

@MainActor private final class RegistryElement: AccessibilityElementReference {
    let traversalIdentifier: Int
    init(_ identifier: Int) { traversalIdentifier = identifier }
}
