import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

public struct NotificationFingerprint: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static func make(for candidate: AccessibilityNotificationCandidate) -> Self {
        // Length-prefixing prevents ambiguous concatenation. Each visible field is digested before it
        // joins the structural material, so callers/cache records never need to retain notification text.
        // Dismissal tokens are capabilities refreshed per snapshot, not notification identity material.
        let values = [candidate.sourceDisplayName, candidate.title, candidate.message].map(fieldDigest)
        let parts = [
            candidate.sourceBundleIdentifier ?? "-", candidate.structuralKind.rawValue,
            candidate.capture.stableContainerIdentifier ?? "-", candidate.capture.coarseStructuralSignature
        ] + values
        let material = parts.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        return .init(rawValue: StableSHA256.hex(Data(material.utf8)))
    }

    private static func fieldDigest(_ field: AccessibilityNotificationCandidate.VisibleField) -> String {
        switch field {
        case .missing: return "missing"
        case .empty: return "empty"
        case .value(let value): return StableSHA256.hex(Data(value.utf8))
        }
    }
}

/// Small standards-based SHA-256 implementation, used to keep DockCatCore Foundation-only on every
/// SwiftPM platform. It is deterministic and is not Swift's process-randomized `hashValue`.
private enum StableSHA256 {
    private static let initial: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
    private static let constants: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]
    static func hex(_ data: Data) -> String {
#if canImport(CryptoKit)
        return CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
#else
        var bytes = [UInt8](data); let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80); while bytes.count % 64 != 56 { bytes.append(0) }
        bytes += (0..<8).reversed().map { UInt8((bitLength >> UInt64($0 * 8)) & 0xff) }
        var hash = initial
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { let j = offset + i * 4; w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j+1]) << 16 | UInt32(bytes[j+2]) << 8 | UInt32(bytes[j+3]) }
            for i in 16..<64 { let s0 = rotate(w[i-15], 7) ^ rotate(w[i-15], 18) ^ (w[i-15] >> 3); let s1 = rotate(w[i-2], 17) ^ rotate(w[i-2], 19) ^ (w[i-2] >> 10); w[i] = w[i-16] &+ s0 &+ w[i-7] &+ s1 }
            var a=hash[0],b=hash[1],c=hash[2],d=hash[3],e=hash[4],f=hash[5],g=hash[6],h=hash[7]
            for i in 0..<64 { let s1=rotate(e,6)^rotate(e,11)^rotate(e,25); let ch=(e&f)^((~e)&g); let t1=h&+s1&+ch&+constants[i]&+w[i]; let s0=rotate(a,2)^rotate(a,13)^rotate(a,22); let maj=(a&b)^(a&c)^(b&c); let t2=s0&+maj; h=g;g=f;f=e;e=d&+t1;d=c;c=b;b=a;a=t1&+t2 }
            hash[0] &+= a; hash[1] &+= b; hash[2] &+= c; hash[3] &+= d
            hash[4] &+= e; hash[5] &+= f; hash[6] &+= g; hash[7] &+= h
        }
        return hash.map { String(format: "%08x", $0) }.joined()
#endif
    }
    private static func rotate(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}
