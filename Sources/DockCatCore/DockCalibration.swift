import Foundation

public struct DockAnchorCalibration: Codable, Equatable, Sendable {
    public static let alongDockRange = -400.0...400.0
    public static let awayFromDockRange = -160.0...400.0

    public var alongDock: Double {
        didSet { alongDock = Self.alongDockRange.clamped(alongDock) }
    }
    public var awayFromDock: Double {
        didSet { awayFromDock = Self.awayFromDockRange.clamped(awayFromDock) }
    }

    public init(alongDock: Double = 0, awayFromDock: Double = 0) {
        self.alongDock = Self.alongDockRange.clamped(alongDock)
        self.awayFromDock = Self.awayFromDockRange.clamped(awayFromDock)
    }

    private enum CodingKeys: String, CodingKey { case alongDock, awayFromDock }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            alongDock: try values.decodeIfPresent(Double.self, forKey: .alongDock) ?? 0,
            awayFromDock: try values.decodeIfPresent(Double.self, forKey: .awayFromDock) ?? 0
        )
    }
}

public struct DockCalibration: Codable, Equatable, Sendable {
    public var home: DockAnchorCalibration
    public var presentation: DockAnchorCalibration

    public init(home: DockAnchorCalibration = .init(), presentation: DockAnchorCalibration = .init()) {
        self.home = home
        self.presentation = presentation
    }

    private enum CodingKeys: String, CodingKey { case home, presentation }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        home = try values.decodeIfPresent(DockAnchorCalibration.self, forKey: .home) ?? .init()
        presentation = try values.decodeIfPresent(
            DockAnchorCalibration.self, forKey: .presentation
        ) ?? .init()
    }

    public var isZero: Bool { self == .init() }
}

public struct DockCalibrationRecord: Codable, Equatable, Sendable {
    public var displayIdentity: DisplayIdentity
    public var dockEdge: DockEdge
    public var calibration: DockCalibration

    public init(displayIdentity: DisplayIdentity, dockEdge: DockEdge, calibration: DockCalibration) {
        self.displayIdentity = displayIdentity
        self.dockEdge = dockEdge
        self.calibration = calibration
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double {
        Swift.min(upperBound, Swift.max(lowerBound, value.isFinite ? value : 0))
    }
}
