import Foundation
import Testing
@testable import PulseCore

@MainActor
struct MonitorDriverTests {
    @Test(arguments: [FeedError.invalidData, .unavailable])
    func readFailurePreservesReasonAndRecoversOnlyOnFreshEvidence(_ error: FeedError) async throws {
        let store = MonitorStore(), feed = SuspendedFeed()
        let driver = MonitorDriver(store: store, feed: feed, interval: .milliseconds(5), clock: { time() })
        driver.start()
        defer { driver.stop() }
        for _ in 0..<100 {
            if await feed.reads == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await feed.complete(1, with: try data())
        for _ in 0..<100 {
            if await feed.reads == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.health == .monitoring)
        await feed.fail(2, with: error)
        for _ in 0..<100 {
            if await feed.reads == 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let expected: FeedHealth = switch error {
        case .invalidData: .invalid
        default: .unavailable
        }
        #expect(store.health == expected)
        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.state == .unknown)
        await feed.complete(3, with: try data(packet(sequence: 2)))
        for _ in 0..<100 {
            if store.health == .monitoring { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(store.health == .monitoring)
        #expect(store.sessions.first?.state == .working)
        driver.stop()
        // Release any next read if scheduling advanced before stop.
        await feed.complete(4, with: try data(packet(sequence: 3)))
    }

    @Test func observesWithoutCreatingAnyViewAndStopsCleanly() async throws {
        let store = MonitorStore(), feed = CountingFeed()
        let driver = MonitorDriver(store: store, feed: feed, interval: .milliseconds(5), tick: .milliseconds(5))
        driver.start()
        driver.start()
        for _ in 0..<100 {
            if await feed.reads >= 3 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await feed.reads >= 3)
        #expect(store.health == .monitoring)
        driver.stop()
        let stopped = await feed.reads
        try await Task.sleep(for: .milliseconds(30))
        #expect(await feed.reads == stopped)
        #expect(store.workingCount == 0)
    }

    @Test func expiryContinuesWhileNextReadIsSuspended() async throws {
        let store = MonitorStore(), feed = SuspendedFeed()
        var updates: [FeedHealth] = []
        let driver = MonitorDriver(store: store, feed: feed, interval: .milliseconds(5), tick: .milliseconds(5),
                                   onUpdate: { updates.append(store.health) })
        driver.start()
        for _ in 0..<100 {
            if await feed.reads == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await feed.complete(1, with: try data(packet(timestamp: Int(MonitorTime.now.wallMS), validity: 80)))
        for _ in 0..<100 {
            if store.health == .stale { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await feed.reads == 2)
        #expect(store.health == .stale)
        #expect(store.workingCount == 0)
        #expect(updates.contains(.monitoring))
        #expect(updates.contains(.stale))
        driver.stop()
        #expect(updates.last == .unavailable)
        await feed.complete(2, with: try data(packet(sequence: 2, timestamp: Int(MonitorTime.now.wallMS))))
        try await Task.sleep(for: .milliseconds(10))
        #expect(store.health == .unavailable)
    }

    @Test func previewNeverReadsTheLiveFeed() async throws {
        let store = MonitorStore(synthetic: true), feed = CountingFeed()
        let driver = MonitorDriver(store: store, feed: feed)
        driver.start()
        try await Task.sleep(for: .milliseconds(20))
        #expect(await feed.reads == 0)
        #expect(store.health == .synthetic)
        driver.stop()
    }

    @Test func lateCancelledReadCannotOverwriteRestartedDriver() async throws {
        let store = MonitorStore(), feed = SuspendedFeed()
        let driver = MonitorDriver(store: store, feed: feed, interval: .seconds(10))
        driver.start()
        for _ in 0..<100 {
            if await feed.reads == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        driver.stop()
        driver.start()
        for _ in 0..<100 {
            if await feed.reads == 2 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await feed.complete(1, with: try data(packet(timestamp: Int(MonitorTime.now.wallMS))))
        try await Task.sleep(for: .milliseconds(10))
        #expect(store.health == .unavailable)
        await feed.complete(2, with: try data(packet(sequence: 2, timestamp: Int(MonitorTime.now.wallMS))))
        for _ in 0..<100 {
            if store.health == .monitoring { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(store.health == .monitoring)
        driver.stop()
    }
}
