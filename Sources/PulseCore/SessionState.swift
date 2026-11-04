import Foundation

public enum SessionState: String, Sendable, CaseIterable {
    case unknown = "UNKNOWN"
    case working = "WORKING"
    case needsAttention = "NEEDS_ATTENTION"
    case turnEnded = "TURN_ENDED"

    public var label: String {
        switch self {
        case .unknown: "Unknown"
        case .working: "Working"
        case .needsAttention: "Needs you"
        case .turnEnded: "Turn ended"
        }
    }

    public var symbol: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .working: "arrow.triangle.2.circlepath"
        case .needsAttention: "exclamationmark.circle.fill"
        case .turnEnded: "minus.circle"
        }
    }
}
