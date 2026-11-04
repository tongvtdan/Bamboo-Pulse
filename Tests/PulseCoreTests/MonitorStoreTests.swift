import Foundation
import Testing
@testable import PulseCore

@MainActor
struct MonitorStoreTests {
    @Test func neverSubstitutesSamplesOnLoss() throws {
        let store = MonitorStore()
        #expect(store.sessions.isEmpty)
        store.receive(try data(), at: time(), epoch: 0)
        #expect(store.workingCount == 1)
        store.fail(.unavailable)
        #expect(store.health == .unavailable)
        #expect(store.sessions.count == 1)
        #expect(store.sessions.allSatisfy { $0.state == .unknown })
        #expect(store.summary == "Status unknown")
        store.receive(Data("malformed".utf8), at: time(), epoch: 0)
        #expect(store.health == .invalid)
        #expect(!store.isSynthetic)
    }

    @Test func previewIsExplicitAndCannotBecomeLive() throws {
        let store = MonitorStore(synthetic: true)
        #expect(store.health == .synthetic)
        #expect(store.sessions.count == 4)
        #expect(store.attentionCount == 1)
        store.receive(try data(), at: time(), epoch: 0)
        store.fail(.unavailable)
        store.refresh(at: time(100000))
        #expect(store.health == .synthetic)
        #expect(store.sessions.count == 4)
    }

    @Test func expiresIndividualRowsAndWholeObservation() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [row(remaining: 300)])), at: time(100), epoch: 0)
        #expect(store.workingCount == 1)
        store.refresh(at: time(300))
        #expect(store.sessions[0].state == .unknown)
        #expect(store.health == .monitoring)
        store.refresh(at: time(2000))
        #expect(store.health == .stale)
        #expect(store.summary == "Status unknown")
    }

    @Test func rejectsExpiredAndFuturePackets() throws {
        for delta in [-1.0, 2000.0] {
            let store = MonitorStore()
            store.receive(try data(), at: time(delta), epoch: 0)
            #expect(store.health == .stale)
            #expect(store.sessions.isEmpty)
        }
    }

    @Test func rejectsSequenceAndTimestampRegressionAndRecoversOnlyOnNewEvidence() throws {
        let store = MonitorStore()
        store.receive(try data(packet(sequence: 2)), at: time(), epoch: 0)
        for sequence in [2, 1] {
            store.receive(try data(packet(sequence: sequence)), at: time(10), epoch: 0)
            #expect(store.health == .invalid)
            #expect(store.workingCount == 0)
        }
        store.receive(try data(packet(sequence: 3, timestamp: 99999)), at: time(20), epoch: 0)
        #expect(store.health == .invalid)
        store.receive(try data(packet(sequence: 4, timestamp: 100020)), at: time(20), epoch: 0)
        #expect(store.health == .monitoring)
        #expect(store.workingCount == 1)
    }

    @Test func retiredGenerationCannotReviveAfterLoss() throws {
        let store = MonitorStore()
        store.receive(try data(), at: time(), epoch: 0)
        store.receive(try data(packet(generation: String(repeating: "c", count: 32))), at: time(10), epoch: 0)
        #expect(store.health == .monitoring)
        store.fail(.unavailable)
        store.receive(try data(packet(sequence: 10)), at: time(20), epoch: 0)
        #expect(store.health == .invalid)
        #expect(store.workingCount == 0)
    }

    @Test func generationRetirementBudgetFailsClosed() throws {
        let store = MonitorStore()
        for index in 0..<33 {
            let generation = String(format: "%032x", index)
            store.receive(try data(packet(generation: generation)), at: time(), epoch: 0)
            #expect(store.health == .monitoring)
        }
        store.receive(try data(packet(generation: String(format: "%032x", 33))), at: time(), epoch: 0)
        #expect(store.health == .invalid)
        #expect(store.workingCount == 0)
    }

    @Test func clockRegressionAndSleepElapsedFailClosed() throws {
        for regressed in [MonitorTime(wallMS: 99999, continuousMS: 501), MonitorTime(wallMS: 100001, continuousMS: 499)] {
            let store = MonitorStore()
            store.receive(try data(), at: time(), epoch: 0)
            store.refresh(at: regressed)
            #expect(store.health == .stale)
        }
        let store = MonitorStore()
        store.receive(try data(), at: time(), epoch: 0)
        store.refresh(at: MonitorTime(wallMS: 100010, continuousMS: 3000))
        #expect(store.health == .stale)
    }

    @Test func epochRejectsLateResponsesWithoutResettingSequence() throws {
        let store = MonitorStore()
        let old = store.beginEpoch()
        store.receive(try data(packet(sequence: 2)), at: time(), epoch: old)
        let current = store.beginEpoch()
        store.receive(try data(packet(sequence: 3)), at: time(), epoch: old)
        #expect(store.health == .unavailable)
        store.receive(try data(packet(sequence: 1)), at: time(), epoch: current)
        #expect(store.health == .invalid)
        store.receive(try data(packet(sequence: 4)), at: time(), epoch: current)
        #expect(store.health == .monitoring)
    }

    @Test func unavailableAndEmptyAreDifferent() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [])), at: time(), epoch: 0)
        #expect(store.summary == "No sessions observed")
        var unavailable = packet(sequence: 2, rows: []); unavailable["monitoring_available"] = false
        store.receive(try data(unavailable), at: time(), epoch: 0)
        #expect(store.health == .unavailable)
        #expect(store.summary == "Status unknown")
    }
}

@Suite("Observed status duration") @MainActor
struct StatusDurationTests {
    private func receive(_ store: MonitorStore, at delta: Int, sequence: Int,
                         state: String = "WORKING", rows: [[String: Any]]? = nil,
                         generation: String = String(repeating: "b", count: 32)) throws {
        store.receive(try data(packet(sequence: sequence, timestamp: 100000 + delta,
            generation: generation, rows: rows ?? [row(state, remaining: state == "NEEDS_ATTENTION" ? 5000 : 120000)])), at: time(Double(delta)), epoch: store.epoch)
    }

    @Test func sameStateEventsAndRefreshesKeepOriginalStartBeyondEventAgeLimit() throws {
        let store = MonitorStore()
        for second in 0...145 {
            try receive(store, at: second * 1000, sequence: second + 1)
            store.refresh(at: time(Double(second * 1000 + 100)))
        }
        #expect(store.sessions[0].statusTiming?.startedContinuousMS == 500)
        #expect(store.sessions[0].statusTiming?.label(at: time(145100)) == "≥2m25s")
    }

    @Test func explicitTransitionsStartNewObservedEpisodes() throws {
        let store = MonitorStore()
        try receive(store, at: 0, sequence: 1)
        try receive(store, at: 1000, sequence: 2, state: "NEEDS_ATTENTION")
        let start = store.sessions[0].statusTiming?.startedContinuousMS
        #expect(start == 1500)
        #expect(store.sessions[0].statusTiming?.isLowerBound == false)
        #expect(store.sessions[0].statusTiming?.label(at: time(1840)) == "0s")
        try receive(store, at: 2000, sequence: 3, state: "NEEDS_ATTENTION")
        #expect(store.sessions[0].statusTiming?.startedContinuousMS == start)
        #expect(store.sessions[0].statusTiming?.label(at: time(2000)) == "1s")
        try receive(store, at: 3000, sequence: 4, state: "TURN_ENDED")
        #expect(store.sessions[0].statusTiming?.label(at: time(3000)) == "0s")
    }

    @Test func sameNamesAndAliasChangesDoNotConflateSessionTimers() throws {
        let store = MonitorStore()
        let second = row("WORKING", id: String(repeating: "c", count: 32), alias: "CX2", remaining: 120000)
        try receive(store, at: 0, sequence: 1)
        try receive(store, at: 1000, sequence: 2, rows: [second, row("WORKING", alias: "CX3", remaining: 120000)])
        #expect(store.sessions[0].name == store.sessions[1].name)
        #expect(store.sessions[0].statusTiming?.startedContinuousMS == 1500)
        #expect(store.sessions[1].statusTiming?.startedContinuousMS == 500)
    }

    @Test func rowExpiryDiscardsDurationAndRecoveryStartsLowerBound() throws {
        let store = MonitorStore()
        try receive(store, at: 0, sequence: 1, rows: [row(remaining: 300)])
        let previous = store.sessions[0].statusTiming
        #expect(previous?.label(at: time(300)) == nil)
        store.refresh(at: time(300))
        #expect(store.sessions[0].statusTiming == nil)
        try receive(store, at: 500, sequence: 2)
        #expect(store.sessions[0].statusTiming?.startedContinuousMS == 1000)
        #expect(store.sessions[0].statusTiming?.isLowerBound == true)
    }

    @Test(arguments: [true, false])
    func freshPacketCannotBridgeExpiredPriorEvidenceWithoutExpiryTick(wholePacket: Bool) throws {
        let store = MonitorStore()
        try receive(store, at: 0, sequence: 1, rows: [row(remaining: wholePacket ? 120000 : 300)])
        let recovery = wholePacket ? 2100 : 500
        try receive(store, at: recovery, sequence: 2)
        #expect(store.sessions[0].statusTiming?.startedContinuousMS == Double(recovery + 500))
        #expect(store.sessions[0].statusTiming?.isLowerBound == true)
    }

    @Test(arguments: [FeedHealth.unavailable, .invalid, .stale])
    func failedObservationDiscardsContinuity(_ health: FeedHealth) throws {
        let store = MonitorStore()
        try receive(store, at: 0, sequence: 1)
        store.fail(health)
        #expect(store.sessions[0].statusTiming == nil)
        try receive(store, at: 1000, sequence: 2)
        #expect(store.sessions[0].statusTiming?.label(at: time(1000)) == "≥0s")
    }

    @Test func missingAndUnknownRowsCannotRetainTiming() throws {
        let store = MonitorStore()
        try receive(store, at: 0, sequence: 1)
        try receive(store, at: 500, sequence: 2, rows: [])
        #expect(store.sessions.isEmpty)
        try receive(store, at: 1000, sequence: 3)
        #expect(store.sessions[0].statusTiming?.startedContinuousMS == 1500)
        try receive(store, at: 1500, sequence: 4, state: "UNKNOWN")
        #expect(store.sessions[0].statusTiming == nil)
        try receive(store, at: 2000, sequence: 5)
        #expect(store.sessions[0].statusTiming?.label(at: time(2000)) == "≥0s")
    }

    @Test func generationAndLifecycleChangesRebaselineEvenWhenStatusIsUnchanged() throws {
        let store = MonitorStore()
        try receive(store, at: 0, sequence: 1)
        let newGeneration = String(repeating: "d", count: 32)
        try receive(store, at: 1000, sequence: 1, generation: newGeneration)
        #expect(store.sessions[0].statusTiming?.startedContinuousMS == 1500)
        store.beginEpoch()
        #expect(store.sessions[0].statusTiming == nil)
        try receive(store, at: 1500, sequence: 2, generation: newGeneration)
        #expect(store.sessions[0].statusTiming?.label(at: time(1500)) == "≥0s")
        let relaunched = MonitorStore()
        try receive(relaunched, at: 1500, sequence: 2, generation: newGeneration)
        #expect(relaunched.sessions[0].statusTiming?.label(at: time(1500)) == "≥0s")
    }

    @Test func clockRegressionRetiresTimingWithoutUsingWallTimeAsDuration() throws {
        let store = MonitorStore()
        try receive(store, at: 0, sequence: 1)
        let timing = try #require(store.sessions[0].statusTiming)
        #expect(timing.label(at: MonitorTime(wallMS: 9999999, continuousMS: 1499)) == "≥0s")
        #expect(timing.label(at: MonitorTime(wallMS: 100001, continuousMS: 499)) == nil)
        store.refresh(at: MonitorTime(wallMS: 99999, continuousMS: 501))
        #expect(store.sessions[0].statusTiming == nil)
    }

    @Test func formatterCoversSecondsMinutesHoursAndInvalidClocks() {
        let timing = StatusTiming(startedContinuousMS: 0, validUntilContinuousMS: 1e12, isLowerBound: false)
        for (seconds, expected) in [(0, "0s"), (24, "24s"), (59, "59s"), (60, "1m00s"),
            (84, "1m24s"), (3599, "59m59s"), (3600, "1h00m"), (3720, "1h02m"), (360000, "100h00m")] {
            #expect(timing.label(at: MonitorTime(wallMS: 0, continuousMS: Double(seconds) * 1000)) == expected)
        }
        #expect(timing.label(at: MonitorTime(wallMS: 0, continuousMS: .nan)) == nil)
        #expect(timing.label(at: MonitorTime(wallMS: 0, continuousMS: .infinity)) == nil)
    }

    @Test func previewDoesNotInventLiveTiming() {
        #expect(MonitorStore(synthetic: true).sessions.allSatisfy { $0.statusTiming == nil })
    }
}
