import XCTest
@testable import DockCatCore

final class DockCatDiagnosticsTests: XCTestCase {
    func testProductIdentityIsCanonical() { XCTAssertEqual(DockCatProductIdentity.fallbackBundleIdentifier, "io.github.pooriat.DockCat") }
    func testRecorderCapacityAndSequence() async {
        let recorder = DockCatDiagnosticEventRecorder(capacity: 3)
        for _ in 0..<5 { await recorder.record(category: .queueMutation, outcome: .changed, revision: 1) }
        let events = await recorder.snapshot()
        XCTAssertEqual(events.map(\.sequence), [3,4,5])
        await recorder.clear(); let cleared = await recorder.snapshot(); XCTAssertTrue(cleared.isEmpty)
    }
    func testSchemaAndPrivacySentinelsAreAbsent() throws {
        let sentinels = ["TOP-SECRET-NOTIFICATION-BODY-12345", "PRIVATE-SOURCE-NAME-67890", "https://example.invalid/private-token"]
        let event = DockCatDiagnosticEvent(sequence: 1, timestamp: Date(timeIntervalSince1970: 0), category: .runtimeTransition, outcome: .changed, detail: "running", revision: 2, generation: 3)
        let snapshot = DockCatDiagnosticSnapshot(generatedAt: Date(timeIntervalSince1970: 1), consistency: .init(queueRevisionStable: true, initialQueueRevision: 2, finalQueueRevision: 2), application: .init(productName: "DockCat", bundleIdentifier: DockCatProductIdentity.fallbackBundleIdentifier, marketingVersion: "0.1.0", buildNumber: "1", macOSVersion: "macOS", processArchitecture: "arm64", buildConfiguration: "Debug"), runtime: .init(lifecycleMode: "running", catState: "sleeping", effectiveVisualMode: "fullMotion", deliveryPaused: false, transitioning: false, recovering: false, runtimeGeneration: 3, currentQueueRevision: 2), sources: .init(internalTestAvailable: true, urlSourceAvailable: true, systemSourceRequested: true, systemSourceHealth: "active", systemSourceReason: nil, nativeBannerCloseRequested: false, exclusionBundleIdentifierCount: 1), queue: .init(currentExists: false, pendingCount: 4, queueLimit: 20, paused: false, recentCompletionCount: 0, recentCompletionCapacity: 100), presentation: .init(sessionExists: false, sessionGeneration: nil, phase: nil, contentRevision: nil, classification: nil, remainingTransientDurationSeconds: nil, dismissalCause: nil, cancellationReason: nil), placement: .init(dockEdge: "bottom", geometryConfidence: "observedVisibleFrameInset", screenFrame: .init(x: 0, y: 0, width: 100, height: 100), visibleFrame: .init(x: 0, y: 20, width: 100, height: 80), requestedDisplayAvailable: true, fallbackUsed: false, calibrationPresent: false, displayToken: "abcd1234"), accessibility: .init(reduceMotion: false, increasedContrast: false, reduceTransparency: false, differentiateWithoutColor: false, accessibilityTrusted: false), recentEvents: [event])
        XCTAssertEqual(snapshot.schemaVersion, 1)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let json = String(decoding: try encoder.encode(snapshot), as: UTF8.self)
        for sentinel in sentinels { XCTAssertFalse(json.contains(sentinel)) }
        for approved in ["0.1.0", "running", "sleeping", "active", "bottom", "reduceMotion"] { XCTAssertTrue(json.contains(approved)) }
        let forbiddenKeys = ["title", "body", "message", "actionURL", "notificationID", "uuid", "sourceDisplayText", "postingBundleIdentifier", "displayName", "rawDisplayIdentifier", "axText", "pid"]
        for key in forbiddenKeys { XCTAssertFalse(json.localizedCaseInsensitiveContains("\"\(key)\"")) }
    }
}
