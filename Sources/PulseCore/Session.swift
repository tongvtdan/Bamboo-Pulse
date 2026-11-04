import Foundation

public struct Session: Identifiable, Sendable, Equatable {
    public let id: String
    public let alias: String
    public let name: String?
    public let state: SessionState
    public let ageMS: Double
    public let remainingMS: Double
    public internal(set) var statusTiming: StatusTiming? = nil
    /// App-local observation continuity; never a provider or authorization identity.
    public internal(set) var observationContinuity: UInt64? = nil

    public var title: String { name ?? "Name unavailable" }
    public var provider: String { "Codex" }

    public func displaying(_ state: SessionState) -> Session {
        Session(id: id, alias: alias, name: name, state: state, ageMS: ageMS, remainingMS: remainingMS,
                statusTiming: state == self.state && state != .unknown ? statusTiming : nil,
                observationContinuity: state != .unknown ? observationContinuity : nil)
    }
}

/// App-observed continuity, separate from source event age and validity.
public struct StatusTiming: Sendable, Equatable {
    public let startedContinuousMS: Double
    public let validUntilContinuousMS: Double
    public let isLowerBound: Bool

    public func label(at time: MonitorTime) -> String? {
        guard time.continuousMS.isFinite, time.continuousMS >= startedContinuousMS,
              time.continuousMS < validUntilContinuousMS else { return nil }
        let seconds = Int(min((time.continuousMS - startedContinuousMS) / 1000, Double(Int.max / 1000)))
        let duration: String
        if seconds < 60 { duration = "\(seconds)s" }
        else if seconds < 3600 { duration = "\(seconds / 60)m\(String(format: "%02d", seconds % 60))s" }
        else { duration = "\(seconds / 3600)h\(String(format: "%02d", seconds / 60 % 60))m" }
        return (isLowerBound ? "≥" : "") + duration
    }
}
