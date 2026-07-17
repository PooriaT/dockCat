import AppKit
import ColorSync
import CoreGraphics
import CryptoKit
import DockCatCore
import OSLog

/// Main-actor catalog and the sole screen-parameter observer. Automatic selection is
/// retained here and never depends on pointer position.
@MainActor
final class DisplayCatalog: ObservableObject {
    @Published private(set) var descriptors: [DisplayDescriptor] = []

    private var tokens: [NSObjectProtocol] = []
    private var retainedRuntimeIdentity: DisplayIdentity?
    private var previousSelection: DisplaySelection?
    private let logger = Logger(subsystem: "com.example.DockCat", category: "Displays")
    var onChange: (@MainActor () -> Void)?

    init() {
        rebuild()
        let center = NotificationCenter.default
        tokens.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuild()
                self?.onChange?()
            }
        })
        tokens.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.rebuild()
                self?.onChange?()
            }
        })
    }

    func stop() {
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        onChange = nil
    }

    func rebuild() {
        let mainNumber = NSScreen.main.flatMap(Self.displayID)
        descriptors = NSScreen.screens.compactMap { screen in
            guard let displayID = Self.displayID(screen) else { return nil }
            let frame = screen.frame
            let visible = screen.visibleFrame
            return DisplayDescriptor(
                identity: Self.identity(for: displayID),
                currentDisplayID: displayID,
                localizedName: screen.localizedName,
                frame: .init(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                visibleFrame: .init(
                    x: visible.minX, y: visible.minY,
                    width: visible.width, height: visible.height
                ),
                isMain: displayID == mainNumber,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                legacyAliases: [String(displayID), screen.localizedName]
            )
        }
    }

    func resolve(
        selection: DisplaySelection,
        safeToRestoreSpecific: Bool
    ) -> DisplayResolutionResult {
        let wasExplicitSelectionChange = previousSelection != nil && previousSelection != selection
        let result = DisplaySelectionResolver.resolve(
            descriptors: descriptors,
            selection: selection,
            retainedRuntimeIdentity: retainedRuntimeIdentity,
            safeToRestoreSpecific: safeToRestoreSpecific || wasExplicitSelectionChange
        )
        previousSelection = selection
        if case .resolved(let resolution) = result {
            retainedRuntimeIdentity = resolution.descriptor.identity
            logger.info(
                "Display resolved token=\(resolution.descriptor.identity.diagnosticsToken, privacy: .public) mode=\(selection.diagnosticsMode, privacy: .public) requestedAvailable=\(resolution.requestedDisplayAvailable, privacy: .public) fallback=\(resolution.usedFallback, privacy: .public)"
            )
        }
        return result
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func identity(for displayID: CGDirectDisplayID) -> DisplayIdentity {
        let stableUUID: String?
        if let unmanaged = CGDisplayCreateUUIDFromDisplayID(displayID) {
            let uuid = unmanaged.takeRetainedValue()
            stableUUID = CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
        } else {
            stableUUID = nil
        }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        let hardwareFingerprint: String?
        if vendor != 0, model != 0, serial != 0 {
            let source = "\(vendor):\(model):\(serial):\(CGDisplayIsBuiltin(displayID) != 0)"
            hardwareFingerprint = SHA256.hash(data: Data(source.utf8))
                .map { String(format: "%02x", $0) }.joined()
        } else {
            hardwareFingerprint = nil
        }
        return .preferred(
            stableUUID: stableUUID,
            hardwareFingerprint: hardwareFingerprint,
            temporaryDisplayID: displayID
        )
    }
}
