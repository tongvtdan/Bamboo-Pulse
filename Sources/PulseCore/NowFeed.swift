import Foundation

public protocol NowFeed: Sendable {
    func read() async throws -> Data
}
