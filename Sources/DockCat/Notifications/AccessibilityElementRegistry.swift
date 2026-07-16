import DockCatCore
import Foundation

struct AccessibilityDismissalToken: Hashable, Sendable {
    let identifier: String
    init(identifier: String = UUID().uuidString) { self.identifier = identifier }
}

/// Main-actor confinement keeps retained AX objects out of Sendable/core models.
@MainActor final class AccessibilityElementRegistry {
    struct Entry {
        let root: any AccessibilityElementReference
        let processIdentifier: Int32
        let expiresAt: Date
    }
    private var entries: [AccessibilityDismissalToken: Entry] = [:]
    private var order: [AccessibilityDismissalToken] = []
    let capacity: Int
    let lifetime: TimeInterval
    private let now: () -> Date

    init(capacity: Int = 64, lifetime: TimeInterval = 8, now: @escaping () -> Date = Date.init) {
        self.capacity = max(1, capacity); self.lifetime = max(0.1, lifetime); self.now = now
    }
    func register(root: any AccessibilityElementReference, processIdentifier: Int32) -> AccessibilityDismissalToken {
        purgeExpired()
        while order.count >= capacity { entries.removeValue(forKey: order.removeFirst()) }
        let token = AccessibilityDismissalToken()
        entries[token] = .init(root: root, processIdentifier: processIdentifier, expiresAt: now().addingTimeInterval(lifetime))
        order.append(token); return token
    }
    func resolve(_ identifier: String) -> Entry? {
        purgeExpired(); return entries[.init(identifier: identifier)]
    }
    func invalidate(_ identifier: String) {
        let token = AccessibilityDismissalToken(identifier: identifier)
        entries.removeValue(forKey: token); order.removeAll { $0 == token }
    }
    func removeAll() { entries.removeAll(); order.removeAll() }
    var count: Int { purgeExpired(); return entries.count }
    private func purgeExpired() {
        let instant = now()
        let expired = Set(entries.compactMap { $0.value.expiresAt <= instant ? $0.key : nil })
        guard !expired.isEmpty else { return }
        expired.forEach { entries.removeValue(forKey: $0) }; order.removeAll { expired.contains($0) }
    }
}
