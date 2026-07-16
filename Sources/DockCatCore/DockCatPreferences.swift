import Foundation

public struct DockCatPreferences: Codable, Equatable {
    public enum SleepingCorner: String, Codable, CaseIterable { case start, end }
    public var enabled = true
    public var pauseAnimations = false
    /// "automatic", "main", or the decimal NSScreenNumber for a selected display.
    public var displaySelection = "automatic"
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

    private enum CodingKeys: String, CodingKey {
        case enabled, pauseAnimations, displaySelection, sleepingCorner, positionOffset
        case dockEndOffset, cardOffset, catScale, defaultTransientDuration, queueLimit
        case transientManuallyDismissible, clickCardOpensAction, remainForQueuedMessages
        case animationSpeed, reducedMotion, disableWalking, idleAnimation
        case systemNotificationsEnabled
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let defaults = Self()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        pauseAnimations = try values.decodeIfPresent(Bool.self, forKey: .pauseAnimations) ?? defaults.pauseAnimations
        displaySelection = try values.decodeIfPresent(String.self, forKey: .displaySelection) ?? defaults.displaySelection
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
    }
}
