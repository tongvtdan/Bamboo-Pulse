public struct NeedsYouPolicy {
    private var generation: String?
    private var epoch: UInt64?
    private var previous: [String: Observation] = [:]

    private struct Observation {
        let state: SessionState
        let continuity: UInt64?
    }

    public init() {}

    public mutating func reset() { self = NeedsYouPolicy() }

    public mutating func update(sessions: [Session], health: FeedHealth, generation: String?,
                                epoch: UInt64, enabled: Bool, synthetic: Bool) -> [String] {
        guard enabled, !synthetic, health == .monitoring, let generation else {
            reset()
            return []
        }
        let current = Dictionary(uniqueKeysWithValues: sessions.map {
            ($0.id, Observation(state: $0.state, continuity: $0.observationContinuity))
        })
        defer {
            previous = current
            self.generation = generation
            self.epoch = epoch
        }
        guard self.generation == generation, self.epoch == epoch else { return [] }
        return sessions.compactMap { session in
            guard session.state == .needsAttention,
                  let continuity = session.observationContinuity,
                  let prior = previous[session.id], prior.continuity == continuity,
                  prior.state == .working || prior.state == .turnEnded else { return nil }
            return session.id
        }
    }
}
