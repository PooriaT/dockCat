import Foundation

public struct DockCatPreferences: Codable, Equatable, Sendable {
    public enum SleepingCorner: String, Codable, CaseIterable, Sendable { case start, end }
    public var enabled = true
    public var pauseAnimations = false
    public var displaySelection = DisplaySelection.automatic
    public var sleepingCorner = SleepingCorner.end
    public var positionOffset = 8.0
    public var dockEndOffset = 0.0
    public var cardOffset = 14.0
    public var catScale = 1.0
    public var defaultTransientDuration = 5.0
    public var queueLimit = 20
    public var transientManuallyDismissible = true
    public var clickCardOpensAction = true
    public var remainForQueuedMessages = true
    public var animationSpeed = 1.0
    public var reducedMotion = false
    public var disableWalking = false
    public var idleAnimation = true
    /// Opt-in gate for the experimental Accessibility-backed source.
    public var systemNotificationsEnabled = false
    /// Experimental, post-acceptance operation; never implies banner suppression.
    public var closeOriginalBannerAfterCapture = false
    public var nativeBannerDismissalExcludedBundleIdentifiers: [String] = []
    public var dockCalibrations: [DockCalibrationRecord] = []

    private enum CodingKeys: String, CodingKey {
        case enabled, pauseAnimations, displaySelection, sleepingCorner, positionOffset
        case dockEndOffset, cardOffset, catScale, defaultTransientDuration, queueLimit
        case transientManuallyDismissible, clickCardOpensAction, remainForQueuedMessages
        case animationSpeed, reducedMotion, disableWalking, idleAnimation
        case systemNotificationsEnabled, closeOriginalBannerAfterCapture
        case nativeBannerDismissalExcludedBundleIdentifiers
        case dockCalibrations
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let defaults = Self()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        pauseAnimations = try values.decodeIfPresent(Bool.self, forKey: .pauseAnimations) ?? defaults.pauseAnimations
        displaySelection = try values.decodeIfPresent(DisplaySelection.self, forKey: .displaySelection) ?? defaults.displaySelection
        sleepingCorner = try values.decodeIfPresent(SleepingCorner.self, forKey: .sleepingCorner) ?? defaults.sleepingCorner
        positionOffset = try values.decodeIfPresent(Double.self, forKey: .positionOffset) ?? defaults.positionOffset
        dockEndOffset = try values.decodeIfPresent(Double.self, forKey: .dockEndOffset) ?? defaults.dockEndOffset
        cardOffset = try values.decodeIfPresent(Double.self, forKey: .cardOffset) ?? defaults.cardOffset
        catScale = try values.decodeIfPresent(Double.self, forKey: .catScale) ?? defaults.catScale
        defaultTransientDuration = try values.decodeIfPresent(Double.self, forKey: .defaultTransientDuration) ?? defaults.defaultTransientDuration
        queueLimit = try values.decodeIfPresent(Int.self, forKey: .queueLimit) ?? defaults.queueLimit
        transientManuallyDismissible = try values.decodeIfPresent(Bool.self, forKey: .transientManuallyDismissible) ?? defaults.transientManuallyDismissible
        clickCardOpensAction = try values.decodeIfPresent(Bool.self, forKey: .clickCardOpensAction) ?? defaults.clickCardOpensAction
        remainForQueuedMessages = try values.decodeIfPresent(Bool.self, forKey: .remainForQueuedMessages) ?? defaults.remainForQueuedMessages
        animationSpeed = try values.decodeIfPresent(Double.self, forKey: .animationSpeed) ?? defaults.animationSpeed
        reducedMotion = try values.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? defaults.reducedMotion
        disableWalking = try values.decodeIfPresent(Bool.self, forKey: .disableWalking) ?? defaults.disableWalking
        idleAnimation = try values.decodeIfPresent(Bool.self, forKey: .idleAnimation) ?? defaults.idleAnimation
        systemNotificationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled) ?? false
        closeOriginalBannerAfterCapture = try values.decodeIfPresent(Bool.self, forKey: .closeOriginalBannerAfterCapture) ?? false
        nativeBannerDismissalExcludedBundleIdentifiers = Self.normalizedBundleIdentifiers(
            try values.decodeIfPresent([String].self, forKey: .nativeBannerDismissalExcludedBundleIdentifiers) ?? []
        )
        let lossyRecords = try values.decodeIfPresent(
            [LossyDockCalibrationRecord].self, forKey: .dockCalibrations
        ) ?? []
        dockCalibrations = Self.normalizedCalibrations(lossyRecords.compactMap(\.value))
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(pauseAnimations, forKey: .pauseAnimations)
        try values.encode(displaySelection, forKey: .displaySelection)
        try values.encode(sleepingCorner, forKey: .sleepingCorner)
        try values.encode(positionOffset, forKey: .positionOffset)
        try values.encode(dockEndOffset, forKey: .dockEndOffset)
        try values.encode(cardOffset, forKey: .cardOffset)
        try values.encode(catScale, forKey: .catScale)
        try values.encode(defaultTransientDuration, forKey: .defaultTransientDuration)
        try values.encode(queueLimit, forKey: .queueLimit)
        try values.encode(transientManuallyDismissible, forKey: .transientManuallyDismissible)
        try values.encode(clickCardOpensAction, forKey: .clickCardOpensAction)
        try values.encode(remainForQueuedMessages, forKey: .remainForQueuedMessages)
        try values.encode(animationSpeed, forKey: .animationSpeed)
        try values.encode(reducedMotion, forKey: .reducedMotion)
        try values.encode(disableWalking, forKey: .disableWalking)
        try values.encode(idleAnimation, forKey: .idleAnimation)
        try values.encode(systemNotificationsEnabled, forKey: .systemNotificationsEnabled)
        try values.encode(closeOriginalBannerAfterCapture, forKey: .closeOriginalBannerAfterCapture)
        try values.encode(
            Self.normalizedBundleIdentifiers(nativeBannerDismissalExcludedBundleIdentifiers),
            forKey: .nativeBannerDismissalExcludedBundleIdentifiers
        )
        try values.encode(Self.normalizedCalibrations(dockCalibrations), forKey: .dockCalibrations)
    }

    public var isNativeBannerDismissalEnabled: Bool {
        systemNotificationsEnabled && closeOriginalBannerAfterCapture
    }

    public static func normalizeBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedBundleIdentifiers(_ values: [String]) -> [String] {
        Array(Set(values.map(normalizeBundleIdentifier).filter { !$0.isEmpty })).sorted()
    }

    public func calibration(for displayIdentity: DisplayIdentity, edge: DockEdge) -> DockCalibration {
        dockCalibrations.last {
            $0.displayIdentity == displayIdentity && $0.dockEdge == edge
        }?.calibration ?? .init()
    }

    public mutating func setCalibration(
        _ calibration: DockCalibration,
        for displayIdentity: DisplayIdentity,
        edge: DockEdge
    ) {
        dockCalibrations.removeAll {
            $0.displayIdentity == displayIdentity && $0.dockEdge == edge
        }
        if !calibration.isZero {
            dockCalibrations.append(.init(
                displayIdentity: displayIdentity, dockEdge: edge, calibration: calibration
            ))
        }
        dockCalibrations = Self.normalizedCalibrations(dockCalibrations)
    }

    public mutating func resetCalibration(for displayIdentity: DisplayIdentity, edge: DockEdge) {
        dockCalibrations.removeAll {
            $0.displayIdentity == displayIdentity && $0.dockEdge == edge
        }
    }

    public mutating func resetAllCalibrations() { dockCalibrations = [] }

    public static func normalizedCalibrations(
        _ records: [DockCalibrationRecord]
    ) -> [DockCalibrationRecord] {
        var normalized: [String: DockCalibrationRecord] = [:]
        for record in records {
            normalized["\(record.displayIdentity.quality.rawValue):\(record.displayIdentity.value):\(record.dockEdge.rawValue)"] = record
        }
        return normalized.values.sorted {
            if $0.displayIdentity != $1.displayIdentity {
                return $0.displayIdentity < $1.displayIdentity
            }
            return $0.dockEdge.rawValue < $1.dockEdge.rawValue
        }
    }
}

private struct LossyDockCalibrationRecord: Decodable {
    let value: DockCalibrationRecord?
    init(from decoder: Decoder) throws {
        value = try? DockCalibrationRecord(from: decoder)
    }
}
