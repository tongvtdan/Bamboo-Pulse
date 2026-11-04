import Foundation

public enum FeedError: Error, Sendable {
    case unavailable, invalidData, outOfOrder, stale, unsupportedMethod
}
