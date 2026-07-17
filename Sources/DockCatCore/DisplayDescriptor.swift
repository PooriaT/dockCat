import Foundation

public struct DisplayDescriptor: Codable, Equatable, Sendable {
    public var identity: DisplayIdentity
    public var currentDisplayID: UInt32
    public var localizedName: String
    public var frame: Rect
    public var visibleFrame: Rect
    public var isMain: Bool
    public var isBuiltIn: Bool
    /// Old decimal screen-number and localized-name values accepted only for migration.
    public var legacyAliases: [String]

    public init(
        identity: DisplayIdentity,
        currentDisplayID: UInt32,
        localizedName: String,
        frame: Rect,
        visibleFrame: Rect,
        isMain: Bool,
        isBuiltIn: Bool,
        legacyAliases: [String] = []
    ) {
        self.identity = identity
        self.currentDisplayID = currentDisplayID
        self.localizedName = localizedName
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.legacyAliases = legacyAliases
    }
}

public struct DisplayResolution: Equatable, Sendable {
    public var descriptor: DisplayDescriptor
    public var requestedDisplayAvailable: Bool
    public var usedFallback: Bool
    public var migratedSelection: DisplaySelection?

    public init(
        descriptor: DisplayDescriptor,
        requestedDisplayAvailable: Bool,
        usedFallback: Bool,
        migratedSelection: DisplaySelection? = nil
    ) {
        self.descriptor = descriptor
        self.requestedDisplayAvailable = requestedDisplayAvailable
        self.usedFallback = usedFallback
        self.migratedSelection = migratedSelection
    }
}

public enum DisplayResolutionResult: Equatable, Sendable {
    case resolved(DisplayResolution)
    case unavailable
}

public enum DisplaySelectionResolver {
    /// Specific-display restoration is allowed only at the caller's safe boundary. The
    /// automatic selection never jumps back to a reconnected display during a process run.
    public static func resolve(
        descriptors: [DisplayDescriptor],
        selection: DisplaySelection,
        retainedRuntimeIdentity: DisplayIdentity?,
        safeToRestoreSpecific: Bool
    ) -> DisplayResolutionResult {
        let ordered = descriptors.sorted(by: deterministicOrder)
        guard !ordered.isEmpty else { return .unavailable }
        let main = ordered.first(where: \.isMain) ?? ordered[0]

        switch selection {
        case .automatic:
            let retained = retainedRuntimeIdentity.flatMap { identity in
                ordered.first { $0.identity == identity }
            }
            return .resolved(.init(
                descriptor: retained ?? main,
                requestedDisplayAvailable: true,
                usedFallback: retainedRuntimeIdentity != nil && retained == nil
            ))
        case .main:
            return .resolved(.init(
                descriptor: main,
                requestedDisplayAvailable: ordered.contains(where: \.isMain),
                usedFallback: !ordered.contains(where: \.isMain)
            ))
        case .specific(let requested):
            let exact = ordered.first { $0.identity == requested }
            let legacy = requested.quality == .legacy
                ? ordered.filter { $0.legacyAliases.contains(requested.value) }
                : []
            let matched = exact ?? (legacy.count == 1 ? legacy[0] : nil)
            let migrated = matched.map { DisplaySelection.specific($0.identity) }

            if let matched {
                if let retainedRuntimeIdentity,
                   retainedRuntimeIdentity != matched.identity,
                   ordered.contains(where: { $0.identity == retainedRuntimeIdentity }),
                   !safeToRestoreSpecific {
                    let retained = ordered.first { $0.identity == retainedRuntimeIdentity }!
                    return .resolved(.init(
                        descriptor: retained,
                        requestedDisplayAvailable: true,
                        usedFallback: true,
                        migratedSelection: migrated
                    ))
                }
                return .resolved(.init(
                    descriptor: matched,
                    requestedDisplayAvailable: true,
                    usedFallback: false,
                    migratedSelection: migrated
                ))
            }

            let retained = retainedRuntimeIdentity.flatMap { identity in
                ordered.first { $0.identity == identity }
            }
            return .resolved(.init(
                descriptor: retained ?? main,
                requestedDisplayAvailable: false,
                usedFallback: true
            ))
        }
    }

    private static func deterministicOrder(_ lhs: DisplayDescriptor, _ rhs: DisplayDescriptor) -> Bool {
        if lhs.isMain != rhs.isMain { return lhs.isMain }
        if lhs.frame.x != rhs.frame.x { return lhs.frame.x < rhs.frame.x }
        if lhs.frame.y != rhs.frame.y { return lhs.frame.y < rhs.frame.y }
        if lhs.localizedName != rhs.localizedName { return lhs.localizedName < rhs.localizedName }
        return lhs.identity < rhs.identity
    }
}
