import ApplicationServices

@MainActor
protocol AccessibilityTrustChecking: AnyObject {
    func isTrusted() -> Bool
    @discardableResult func requestTrust() -> Bool
}

@MainActor
final class AccessibilityTrustController: AccessibilityTrustChecking {
    func isTrusted() -> Bool { AXIsProcessTrusted() }

    @discardableResult
    func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
