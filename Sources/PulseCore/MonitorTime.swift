import Foundation

public struct MonitorTime: Sendable {
    public let wallMS: Double
    public let continuousMS: Double
    private static let origin = ContinuousClock.now

    public init(wallMS: Double, continuousMS: Double) {
        self.wallMS = wallMS
        self.continuousMS = continuousMS
    }

    public static var now: MonitorTime {
        let elapsed = origin.duration(to: .now).components
        return MonitorTime(
            wallMS: Date().timeIntervalSince1970 * 1000,
            continuousMS: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        )
    }
}
