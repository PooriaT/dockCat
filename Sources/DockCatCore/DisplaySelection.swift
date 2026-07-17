import Foundation

public enum DisplaySelection: Equatable, Hashable, Sendable, Codable {
    case automatic
    case main
    case specific(DisplayIdentity)

    private enum CodingKeys: String, CodingKey { case mode, identity }
    private enum Mode: String, Codable { case automatic, main, specific }

    public init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            switch legacy {
            case "automatic": self = .automatic
            case "main": self = .main
            default: self = .specific(.legacy(legacy))
            }
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Mode.self, forKey: .mode) {
        case .automatic: self = .automatic
        case .main: self = .main
        case .specific:
            self = .specific(try values.decode(DisplayIdentity.self, forKey: .identity))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .automatic:
            try values.encode(Mode.automatic, forKey: .mode)
        case .main:
            try values.encode(Mode.main, forKey: .mode)
        case .specific(let identity):
            try values.encode(Mode.specific, forKey: .mode)
            try values.encode(identity, forKey: .identity)
        }
    }

    public var diagnosticsMode: String {
        switch self {
        case .automatic: "automatic"
        case .main: "main"
        case .specific: "specific"
        }
    }
}
