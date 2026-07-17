import Foundation
import XCTest
@testable import DockCatCore

final class NotificationFingerprintAndCacheTests: XCTestCase, @unchecked Sendable {
    func testFingerprintIsStableAndSHA256Sized() throws {
        let candidate = try AccessibilityNotificationParser().parse(AXFixtures.banner()).get()
        let first = NotificationFingerprint.make(for: candidate)
        XCTAssertEqual(first, NotificationFingerprint.make(for: candidate))
        XCTAssertEqual(first.rawValue, "1fbe539c25efba8590eb55b2837fdbce77beef2798a7d1caea884965bd2abb97")
        XCTAssertEqual(first.rawValue.count, 64)
    }
    func testEquivalentCallbacksMatchButDistinctBodiesDoNot() throws {
        let parser = AccessibilityNotificationParser()
        let first = try parser.parse(AXFixtures.banner(sequence: 1)).get()
        let repeated = try parser.parse(AXFixtures.banner(sequence: 999)).get()
        let distinct = try parser.parse(AXFixtures.banner(body: "A different invented result.")).get()
        XCTAssertEqual(NotificationFingerprint.make(for: first), NotificationFingerprint.make(for: repeated))
        XCTAssertNotEqual(NotificationFingerprint.make(for: first), NotificationFingerprint.make(for: distinct))
    }
    func testMinorActionStructureChangesDoNotSplitFingerprint() throws {
        let parser = AccessibilityNotificationParser()
        let plain = try parser.parse(AXFixtures.banner()).get()
        let withButton = try parser.parse(AXFixtures.banner(extraChildren: [.init(role: "AXButton", identifier: "action", title: "Aceptar")])).get()
        XCTAssertEqual(NotificationFingerprint.make(for: plain), NotificationFingerprint.make(for: withButton))
    }
    func testRetentionExpiryAndExplicitRemoval() async {
        let clock = TestClock(); let cache = NotificationDeduplicationCache(retention: 5, capacity: 2, now: clock.now)
        let fingerprint = NotificationFingerprint(rawValue: "digest-a")
        let accepted = await cache.observe(fingerprint, metadata: .init(sequence: 1))
        let duplicate = await cache.observe(fingerprint, metadata: .init(sequence: 2))
        XCTAssertEqual(accepted, .accepted); XCTAssertEqual(duplicate, .duplicate)
        clock.advance(5)
        let expired = await cache.observe(fingerprint, metadata: .init(sequence: 3))
        XCTAssertEqual(expired, .expiredReplacement)
        await cache.remove(fingerprint)
        let contains = await cache.contains(fingerprint); XCTAssertFalse(contains)
    }
    func testCapacityEvictsOldestDeterministically() async {
        let clock = TestClock(); let cache = NotificationDeduplicationCache(retention: 100, capacity: 2, now: clock.now)
        let a = NotificationFingerprint(rawValue: "a"), b = NotificationFingerprint(rawValue: "b"), c = NotificationFingerprint(rawValue: "c")
        _ = await cache.observe(a, metadata: .init(sequence: 1)); clock.advance(1)
        _ = await cache.observe(b, metadata: .init(sequence: 2)); clock.advance(1)
        _ = await cache.observe(c, metadata: .init(sequence: 3))
        let count = await cache.count(), containsA = await cache.contains(a), containsB = await cache.contains(b)
        XCTAssertEqual(count, 2); XCTAssertFalse(containsA); XCTAssertTrue(containsB)
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock(); private var date = Date(timeIntervalSince1970: 1_000)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}
