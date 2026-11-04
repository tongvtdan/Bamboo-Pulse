import Foundation

public enum FeedHealth: String, Sendable {
    case connecting = "Connecting to local feed"
    case monitoring = "Codex feed available"
    case unavailable = "Local feed unavailable"
    case invalid = "Invalid observation"
    case stale = "Observation expired"
    case synthetic = "Synthetic preview · no live data"
}
