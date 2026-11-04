import Foundation

/// Owned by the application delegate, never by a popover or its task modifier.
@MainActor
public final class MonitorDriver {
    private let store: MonitorStore
    private let feed: any NowFeed
    private let interval: Duration
    private let tick: Duration
    private let clock: @Sendable () -> MonitorTime
    private let onUpdate: @MainActor () -> Void
    private var polling: Task<Void, Never>?
    private var expiry: Task<Void, Never>?

    public init(store: MonitorStore, feed: any NowFeed, interval: Duration = .milliseconds(500),
                tick: Duration = .milliseconds(100), clock: @escaping @Sendable () -> MonitorTime = { .now },
                onUpdate: @escaping @MainActor () -> Void = {}) {
        self.store = store
        self.feed = feed
        self.interval = interval
        self.tick = tick
        self.clock = clock
        self.onUpdate = onUpdate
    }

    public func start() {
        guard polling == nil, !store.isSynthetic else { return }
        let token = store.beginEpoch()
        onUpdate()
        polling = Task { [store, feed, interval, clock, onUpdate] in
            while !Task.isCancelled {
                do {
                    let data = try await feed.read()
                    guard !Task.isCancelled else { return }
                    store.receive(data, at: clock(), epoch: token)
                } catch FeedError.invalidData {
                    guard !Task.isCancelled else { return }
                    store.fail(.invalid, epoch: token)
                } catch {
                    guard !Task.isCancelled else { return }
                    store.fail(.unavailable, epoch: token)
                }
                onUpdate()
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
        expiry = Task { [store, tick, clock, onUpdate] in
            while !Task.isCancelled {
                guard store.epoch == token else { return }
                store.refresh(at: clock())
                onUpdate()
                do { try await Task.sleep(for: tick) } catch { return }
            }
        }
    }

    public func stop() {
        store.beginEpoch()
        onUpdate()
        polling?.cancel()
        expiry?.cancel()
        polling = nil
        expiry = nil
    }

    deinit { polling?.cancel(); expiry?.cancel() }
}
