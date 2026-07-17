import XCTest
@testable import DockCatCore

final class DisplaySelectionTests: XCTestCase {
    private let frame = Rect(x: 0, y: 0, width: 1_440, height: 900)

    func testAutomaticDefaultsToMainAndRetainsConnectedDisplay() {
        let main = descriptor("main", x: 0, isMain: true)
        let other = descriptor("other", x: 1_440)
        XCTAssertEqual(
            resolved([other, main], .automatic, retained: nil).descriptor.identity,
            main.identity
        )
        XCTAssertEqual(
            resolved([main, other], .automatic, retained: other.identity).descriptor.identity,
            other.identity
        )
    }

    func testAutomaticFallsBackAndDoesNotJumpBackAfterReconnect() {
        let main = descriptor("main", x: 0, isMain: true)
        let old = descriptor("old", x: -1_440)
        let fallback = resolved([main], .automatic, retained: old.identity)
        XCTAssertEqual(fallback.descriptor.identity, main.identity)
        XCTAssertTrue(fallback.usedFallback)

        let afterReconnect = resolved([main, old], .automatic, retained: main.identity)
        XCTAssertEqual(afterReconnect.descriptor.identity, main.identity)
    }

    func testNoMainUsesDeterministicGeometryOrdering() {
        let right = descriptor("right", x: 500)
        let left = descriptor("left", x: -500)
        XCTAssertEqual(
            resolved([right, left], .automatic, retained: nil).descriptor.identity,
            left.identity
        )
    }

    func testSpecificMissingPreservesRequestAndUsesRuntimeFallback() {
        let main = descriptor("main", x: 0, isMain: true)
        let requested = DisplayIdentity(value: "missing", quality: .stableUUID)
        let resolution = resolved([main], .specific(requested), retained: nil)
        XCTAssertEqual(resolution.descriptor.identity, main.identity)
        XCTAssertFalse(resolution.requestedDisplayAvailable)
        XCTAssertTrue(resolution.usedFallback)
        XCTAssertNil(resolution.migratedSelection)
    }

    func testSpecificReconnectIsDeferredUntilSafeBoundary() {
        let fallback = descriptor("fallback", x: 0, isMain: true)
        let requested = descriptor("requested", x: 1_440)
        let deferred = resolved(
            [fallback, requested], .specific(requested.identity),
            retained: fallback.identity, safe: false
        )
        XCTAssertEqual(deferred.descriptor.identity, fallback.identity)
        XCTAssertTrue(deferred.requestedDisplayAvailable)
        XCTAssertTrue(deferred.usedFallback)

        let restored = resolved(
            [fallback, requested], .specific(requested.identity),
            retained: fallback.identity, safe: true
        )
        XCTAssertEqual(restored.descriptor.identity, requested.identity)
        XCTAssertFalse(restored.usedFallback)
    }

    func testLegacyNumberAndUniqueNameMigrateButDuplicateNameDoesNotCollide() {
        var first = descriptor("first", x: 0, isMain: true, name: "Studio Display")
        first.legacyAliases = ["17", "Studio Display"]
        var second = descriptor("second", x: 1_440, name: "Studio Display")
        second.legacyAliases = ["21", "Studio Display"]

        let number = resolved([first, second], .specific(.legacy("17")), retained: nil)
        XCTAssertEqual(number.descriptor.identity, first.identity)
        XCTAssertEqual(number.migratedSelection, .specific(first.identity))

        let duplicateName = resolved(
            [first, second], .specific(.legacy("Studio Display")), retained: nil
        )
        XCTAssertFalse(duplicateName.requestedDisplayAvailable)
        XCTAssertTrue(duplicateName.usedFallback)
    }

    func testNoDisplaysReturnsTypedUnavailable() {
        XCTAssertEqual(
            DisplaySelectionResolver.resolve(
                descriptors: [], selection: .automatic,
                retainedRuntimeIdentity: nil, safeToRestoreSpecific: true
            ),
            .unavailable
        )
    }

    func testDiagnosticsTokenDoesNotContainIdentityOrSerialMaterial() {
        let identity = DisplayIdentity(
            value: "vendor:model:very-sensitive-serial", quality: .hardwareFingerprint
        )
        XCTAssertFalse(identity.diagnosticsToken.contains(identity.value))
        XCTAssertFalse(identity.diagnosticsToken.contains("serial"))
        XCTAssertEqual(identity.diagnosticsToken.count, 8)
    }

    func testStrongIdentityWinsOverHardwareAndTemporaryFallbacks() {
        XCTAssertEqual(
            DisplayIdentity.preferred(
                stableUUID: "PUBLIC-UUID", hardwareFingerprint: "hashed-hardware",
                temporaryDisplayID: 42
            ),
            .init(value: "public-uuid", quality: .stableUUID)
        )
        XCTAssertEqual(
            DisplayIdentity.preferred(
                stableUUID: nil, hardwareFingerprint: "hashed-hardware",
                temporaryDisplayID: 42
            ).quality,
            .hardwareFingerprint
        )
        XCTAssertEqual(
            DisplayIdentity.preferred(
                stableUUID: nil, hardwareFingerprint: nil, temporaryDisplayID: 42
            ),
            .init(value: "42", quality: .temporary)
        )
    }

    private func resolved(
        _ descriptors: [DisplayDescriptor],
        _ selection: DisplaySelection,
        retained: DisplayIdentity?,
        safe: Bool = true
    ) -> DisplayResolution {
        guard case .resolved(let value) = DisplaySelectionResolver.resolve(
            descriptors: descriptors,
            selection: selection,
            retainedRuntimeIdentity: retained,
            safeToRestoreSpecific: safe
        ) else {
            XCTFail("Expected a display resolution")
            fatalError()
        }
        return value
    }

    private func descriptor(
        _ id: String,
        x: Double,
        isMain: Bool = false,
        name: String = "Display"
    ) -> DisplayDescriptor {
        .init(
            identity: .init(value: id, quality: .stableUUID),
            currentDisplayID: UInt32(abs(id.hashValue % 10_000)),
            localizedName: name,
            frame: .init(x: x, y: 0, width: frame.width, height: frame.height),
            visibleFrame: .init(x: x, y: 70, width: frame.width, height: frame.height - 70),
            isMain: isMain,
            isBuiltIn: isMain
        )
    }
}
