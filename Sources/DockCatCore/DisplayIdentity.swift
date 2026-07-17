import Foundation

/// A public-API display identifier. `value` is either a public CoreGraphics UUID,
/// a hash of public hardware metadata, or a temporary/legacy token. Display identity
/// can still be imperfect when a display or adapter does not expose stable metadata.
public struct DisplayIdentity: Codable, Equatable, Hashable, Sendable, Comparable {
    public enum PersistenceQuality: String, Codable, Equatable, Sendable {
        case stableUUID
        case hardwareFingerprint
        case temporary
        case legacy
    }

    public var value: String
    public var quality: PersistenceQuality

    public init(value: String, quality: PersistenceQuality) {
        self.value = value
        self.quality = quality
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.quality.rawValue != rhs.quality.rawValue {
            return lhs.quality.rawValue < rhs.quality.rawValue
        }
        return lhs.value < rhs.value
    }

    /// A non-sensitive token suitable for logs. It deliberately does not reveal the
    /// persisted UUID, fingerprint, serial-derived hash, or transient display number.
    public var diagnosticsToken: String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(quality.rawValue):\(value)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(String(hash, radix: 16).prefix(8))
    }

    public static func legacy(_ value: String) -> Self {
        .init(value: value, quality: .legacy)
    }

    public static func preferred(
        stableUUID: String?,
        hardwareFingerprint: String?,
        temporaryDisplayID: UInt32
    ) -> Self {
        if let stableUUID, !stableUUID.isEmpty {
            return .init(value: stableUUID.lowercased(), quality: .stableUUID)
        }
        if let hardwareFingerprint, !hardwareFingerprint.isEmpty {
            return .init(value: hardwareFingerprint, quality: .hardwareFingerprint)
        }
        return .init(value: String(temporaryDisplayID), quality: .temporary)
    }
}
