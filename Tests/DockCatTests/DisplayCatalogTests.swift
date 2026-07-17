import DockCatCore
import XCTest
@testable import DockCat

@MainActor
final class DisplayCatalogTests: XCTestCase {
    func testEnteringAutomaticIgnoresDisplayRetainedBySpecificMode() {
        let main = descriptor("main", x: 0, isMain: true)
        let selected = descriptor("selected", x: 1_440)
        let retained = DisplayCatalog.retainedIdentityForResolution(
            selection: .automatic,
            previousSelection: .specific(selected.identity),
            retainedRuntimeIdentity: selected.identity
        )

        XCTAssertNil(retained)
        guard case .resolved(let resolution) = DisplaySelectionResolver.resolve(
            descriptors: [selected, main],
            selection: .automatic,
            retainedRuntimeIdentity: retained,
            safeToRestoreSpecific: true
        ) else {
            return XCTFail("Expected Automatic to resolve a display")
        }
        XCTAssertEqual(resolution.descriptor.identity, main.identity)
    }

    func testAutomaticRetainsItsOwnRuntimeDisplayAfterInitialResolution() {
        let retained = DisplayIdentity(value: "retained", quality: .stableUUID)
        XCTAssertEqual(
            DisplayCatalog.retainedIdentityForResolution(
                selection: .automatic,
                previousSelection: .automatic,
                retainedRuntimeIdentity: retained
            ),
            retained
        )
    }

    private func descriptor(
        _ identity: String, x: Double, isMain: Bool = false
    ) -> DisplayDescriptor {
        .init(
            identity: .init(value: identity, quality: .stableUUID),
            currentDisplayID: isMain ? 1 : 2,
            localizedName: identity.capitalized,
            frame: .init(x: x, y: 0, width: 1_440, height: 900),
            visibleFrame: .init(x: x, y: 70, width: 1_440, height: 830),
            isMain: isMain,
            isBuiltIn: isMain
        )
    }
}
