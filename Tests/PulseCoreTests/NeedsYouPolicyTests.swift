import Testing
@testable import PulseCore

struct NeedsYouPolicyTests {
    private func session(_ state: SessionState, id: String = "one") -> Session {
        Session(id: id, alias: "CX1", name: "Same title", state: state, ageMS: 0, remainingMS: 1000,
                observationContinuity: state == .unknown ? nil : 1)
    }

    @Test func firstAttentionIsSilentAndOnlyContinuousTransitionsAlert() {
        var policy = NeedsYouPolicy()
        func step(_ state: SessionState) -> [String] {
            policy.update(sessions: [session(state)], health: .monitoring, generation: "g", epoch: 0, enabled: true, synthetic: false)
        }
        #expect(step(.needsAttention).isEmpty)
        #expect(step(.working).isEmpty)
        #expect(step(.needsAttention) == ["one"])
        #expect(step(.needsAttention).isEmpty)
        #expect(step(.turnEnded).isEmpty)
        #expect(step(.needsAttention) == ["one"])
    }

    @Test func unknownMissingAndNewRowsCannotInventResolvedRequests() {
        var policy = NeedsYouPolicy()
        func step(_ states: [Session]) -> [String] {
            policy.update(sessions: states, health: .monitoring, generation: "g", epoch: 0, enabled: true, synthetic: false)
        }
        #expect(step([session(.working)]).isEmpty)
        #expect(step([session(.unknown)]).isEmpty)
        #expect(step([session(.needsAttention)]).isEmpty)
        #expect(step([session(.working)]).isEmpty)
        #expect(step([]).isEmpty)
        #expect(step([session(.needsAttention)]).isEmpty)
        #expect(step([session(.needsAttention, id: "new")]).isEmpty)
    }

    @Test func identicalTitlesHaveIndependentEpisodes() {
        var policy = NeedsYouPolicy()
        _ = policy.update(sessions: [session(.working, id: "one"), session(.working, id: "two")],
            health: .monitoring, generation: "g", epoch: 0, enabled: true, synthetic: false)
        #expect(policy.update(sessions: [session(.needsAttention, id: "one"), session(.needsAttention, id: "two")],
            health: .monitoring, generation: "g", epoch: 0, enabled: true, synthetic: false) == ["one", "two"])
    }

    @Test func generationEpochLossDisableAndPreviewAlwaysRebaseline() {
        for boundary in ["generation", "epoch", "unavailable", "stale", "invalid", "disabled", "preview"] {
            var policy = NeedsYouPolicy()
            _ = policy.update(sessions: [session(.working)], health: .monitoring, generation: "g", epoch: 0, enabled: true, synthetic: false)
            let generation = boundary == "generation" ? "new" : "g"
            let epoch: UInt64 = boundary == "epoch" ? 1 : 0
            let health: FeedHealth = switch boundary {
            case "unavailable": .unavailable
            case "stale": .stale
            case "invalid": .invalid
            default: .monitoring
            }
            #expect(policy.update(sessions: [session(.needsAttention)], health: health, generation: generation,
                epoch: epoch, enabled: boundary != "disabled", synthetic: boundary == "preview").isEmpty)
            #expect(policy.update(sessions: [session(.needsAttention)], health: .monitoring, generation: generation,
                epoch: epoch, enabled: true, synthetic: false).isEmpty)
        }
    }

    @Test @MainActor func rowExpiryRecoveryBeforeTickIsSilent() throws {
        try expiryRecoveryBeforeTickIsSilent(wholePacket: false)
    }

    @Test func absentContinuityCannotArmAnAlert() {
        var policy = NeedsYouPolicy()
        var working = session(.working)
        working.observationContinuity = nil
        _ = policy.update(sessions: [working], health: .monitoring, generation: "g", epoch: 0, enabled: true, synthetic: false)
        #expect(policy.update(sessions: [session(.needsAttention)], health: .monitoring,
            generation: "g", epoch: 0, enabled: true, synthetic: false).isEmpty)
    }

    @Test @MainActor func packetExpiryRecoveryBeforeTickIsSilent() throws {
        try expiryRecoveryBeforeTickIsSilent(wholePacket: true)
    }

    @MainActor private func expiryRecoveryBeforeTickIsSilent(wholePacket: Bool) throws {
        let store = MonitorStore()
        var policy = NeedsYouPolicy()
        let otherID = String(repeating: "c", count: 32)
        func receive(_ state: String, sequence: Int, delta: Int, remaining: Int,
                     otherState: String = "NEEDS_ATTENTION") throws -> [String] {
            store.receive(try data(packet(sequence: sequence, timestamp: 100000 + delta, rows: [
                row(state, remaining: remaining),
                row(otherState, id: otherID, alias: "CX2", remaining: 5000),
            ])), at: time(Double(delta)), epoch: store.epoch)
            return policy.update(sessions: store.sessions, health: store.health,
                generation: store.observationGeneration, epoch: store.epoch, enabled: true, synthetic: false)
        }
        #expect(try receive("WORKING", sequence: 1, delta: 0,
            remaining: wholePacket ? 120000 : 300, otherState: "WORKING").isEmpty)
        let recovery = wholePacket ? 2100 : 500
        // No refresh or policy callback occurs between the old lease and fresh recovery.
        let recoveredAlerts = try receive("NEEDS_ATTENTION", sequence: 2, delta: recovery, remaining: 5000)
        #expect(store.health == .monitoring)
        #expect(store.sessions[0].statusTiming?.isLowerBound == true)
        #expect(recoveredAlerts == (wholePacket ? [] : [otherID]))
        #expect(try receive("NEEDS_ATTENTION", sequence: 3, delta: recovery + 100, remaining: 5000).isEmpty)
        #expect(try receive("WORKING", sequence: 4, delta: recovery + 200, remaining: 120000).isEmpty)
        #expect(try receive("NEEDS_ATTENTION", sequence: 5, delta: recovery + 300, remaining: 5000)
            == [String(repeating: "a", count: 32)])
        #expect(try receive("NEEDS_ATTENTION", sequence: 6, delta: recovery + 400, remaining: 5000).isEmpty)
    }
}
