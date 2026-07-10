import Foundation

struct DockCatPreferences: Codable, Equatable {
    enum SleepingCorner: String, Codable, CaseIterable { case start, end }
    var enabled = true
    var pauseAnimations = false
    /// "automatic", "main", or the decimal NSScreenNumber for a selected display.
    var displaySelection = "automatic"
    var sleepingCorner = SleepingCorner.end
    var positionOffset = 8.0
    var dockEndOffset = 0.0
    var cardOffset = 14.0
    var catScale = 1.0
    var defaultTransientDuration = 5.0
    var queueLimit = 20
    var transientManuallyDismissible = true
    var clickCardOpensAction = true
    var remainForQueuedMessages = true
    var animationSpeed = 1.0
    var reducedMotion = false
    var disableWalking = false
    var idleAnimation = true
}
