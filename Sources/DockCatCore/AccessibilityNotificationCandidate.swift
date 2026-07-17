import Foundation

/// A Foundation-only semantic view of visible Accessibility data. It never owns an AX object.
public struct AccessibilityNotificationCandidate: Sendable, Equatable {
    public enum VisibleField: Sendable, Equatable {
        case missing
        case empty
        case value(String)

        public var displayValue: String? {
            guard case .value(let value) = self else { return nil }
            return value
        }
    }

    public enum StructuralKind: String, Sendable { case banner, alert, unknown }
    public enum LifecycleHint: String, Sendable { case appeared, changed, disappeared, unknown }
    public struct ActionDescriptor: Sendable, Equatable {
        public let identifier: String?
        public let label: String?
        public let supportedActions: [String]
        public init(identifier: String?, label: String?, supportedActions: [String]) {
            self.identifier = identifier; self.label = label; self.supportedActions = supportedActions
        }
    }
    public struct CaptureMetadata: Sendable, Equatable {
        public let sequence: UInt64
        public let processIdentifier: Int32
        public let stableContainerIdentifier: String?
        public let coarseStructuralSignature: String
        public let traversalWasTruncated: Bool
        /// Child-index path from the retained snapshot root to the parser-selected
        /// notification container. It is structural metadata, never an AX reference.
        public let notificationSubtreePath: [Int]
        public init(sequence: UInt64, processIdentifier: Int32, stableContainerIdentifier: String?,
                    coarseStructuralSignature: String, traversalWasTruncated: Bool,
                    notificationSubtreePath: [Int] = []) {
            self.sequence = sequence; self.processIdentifier = processIdentifier
            self.stableContainerIdentifier = stableContainerIdentifier
            self.coarseStructuralSignature = coarseStructuralSignature
            self.traversalWasTruncated = traversalWasTruncated
            self.notificationSubtreePath = notificationSubtreePath
        }
    }

    public let sourceBundleIdentifier: String?
    public let sourceDisplayName: VisibleField
    public let title: VisibleField
    public let message: VisibleField
    public let actions: [ActionDescriptor]
    public let structuralKind: StructuralKind
    public let lifecycleHint: LifecycleHint
    public let capture: CaptureMetadata
    public let opaqueDismissalTokenIdentifier: String?
}

public enum AccessibilityNotificationRejection: String, Error, Sendable, Equatable {
    case unrelatedStructure
    case insufficientVisibleContent
    case hiddenWithoutNotificationStructure
    case ambiguousNotificationStructure
    case disappeared
    case excludedOrigin
    case excludedInternalStructure
}
