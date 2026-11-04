import Foundation
import PulseCore
import Testing

@Suite("Coverage and recovery") @MainActor
struct MonitoringStatusTests {
    @Test func freshUnknownStatusDoesNotImplyUpdatesAreOutOfDate() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [row("UNKNOWN")])), at: time(), epoch: 0)
        let status = MonitoringStatus(store: store)
        #expect(store.health == .monitoring)
        #expect(store.sessions.first?.state == .unknown)
        #expect(status.headline == "Connected")
        #expect(status.detail == "Pulse can’t determine the current status of sessions marked Unknown.")
        #expect(status.recovery == nil)
    }

    @Test func emptyIsObservedCoverageNotGlobalAbsence() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [])), at: time(), epoch: 0)
        let status = MonitoringStatus(store: store)
        #expect(status.headline == "No sessions observed")
        #expect(status.inventory == "0 sessions observed")
        #expect(status.detail.contains("being reported to Pulse"))
        #expect(status.recovery == nil)
        #expect(status.showsPopoverGuidance)
    }

    @Test func healthySessionsHaveNoRecoveryAdviceAndUnknownStaysExplicit() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [row(remaining: 300)])), at: time(), epoch: 0)
        let before = MonitoringStatus(store: store)
        #expect(before.headline == "Connected")
        #expect(before.inventory == "1 session observed")
        #expect(!before.showsPopoverGuidance)
        store.refresh(at: time(300))
        let after = MonitoringStatus(store: store)
        #expect(store.health == .monitoring)
        #expect(store.sessions.first?.state == .unknown)
        #expect(after.headline == before.headline)
        #expect(after.detail.contains("Unknown"))
        #expect(after.recovery == nil)
    }

    @Test func connectingAndProducerUnavailableNeverClaimZeroSessions() throws {
        let store = MonitorStore()
        let connecting = MonitoringStatus(store: store)
        #expect(connecting.headline == "Connecting…")
        #expect(connecting.recovery == nil)
        #expect(connecting.inventory == "Current session count unknown")
        var unavailable = packet(rows: [])
        unavailable["monitoring_available"] = false
        store.receive(try data(unavailable), at: time(), epoch: 0)
        let status = MonitoringStatus(store: store)
        #expect(status.headline == "Connection unavailable")
        #expect(status.inventory == connecting.inventory)
        #expect(!status.detail.contains("runtime"))
        #expect(status.recovery?.contains("automatically") == true)
    }

    @Test func rejectedObservationDoesNotDiagnoseVersionAndRecoversOnlyOnAcceptedEvidence() throws {
        let store = MonitorStore()
        store.receive(try data(), at: time(), epoch: 0)
        var bad = packet(sequence: 2)
        bad["version"] = 2
        store.receive(try data(bad), at: time(1), epoch: 0)
        let invalid = MonitoringStatus(store: store)
        #expect(invalid.headline == "Couldn’t read session updates")
        #expect(invalid.detail.contains("couldn’t be read"))
        #expect(invalid.inventory == "1 previous session · status unknown")
        #expect(invalid.recovery?.contains("automatically") == true)
        store.receive(try data(), at: time(2), epoch: 0)
        #expect(MonitoringStatus(store: store).headline == invalid.headline)
        store.receive(try data(packet(sequence: 3, timestamp: 100003)), at: time(3), epoch: 0)
        #expect(MonitoringStatus(store: store).headline == "Connected")
        #expect(MonitoringStatus(store: store).recovery == nil)
    }

    @Test(arguments: [false, true])
    func expiryWithAndWithoutRetainedRowsIsNotEmptyCoverage(_ hasRows: Bool) throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: hasRows ? [row()] : [])), at: time(), epoch: 0)
        store.refresh(at: time(2000))
        let status = MonitoringStatus(store: store)
        #expect(status.headline == "Updates paused")
        #expect(status.detail.contains("out of date"))
        #expect(status.inventory.contains("unknown"))
        #expect(!status.inventory.contains("observed"))
        #expect(status.showsPopoverGuidance)
        #expect(store.sessions.allSatisfy { $0.state == .unknown })
    }

    @Test func transportLossDoesNotReportRetainedInventoryAsCurrent() throws {
        let store = MonitorStore()
        store.receive(try data(), at: time(), epoch: 0)
        store.fail(.unavailable)
        let status = MonitoringStatus(store: store)
        #expect(status.inventory == "1 previous session · status unknown")
        #expect(status.headline == "Connection unavailable")
        #expect(status.recovery?.contains("automatically") == true)
    }

    @Test func previewCannotSuggestLiveSetupSucceeded() throws {
        let store = MonitorStore(synthetic: true)
        store.receive(try data(), at: time(), epoch: 0)
        let status = MonitoringStatus(store: store)
        #expect(status.headline == "Demo mode")
        #expect(status.inventory == "4 sample sessions")
        #expect(status.recovery == nil)
        #expect(status.detail.contains("not your live activity"))
        #expect(status.showsPopoverGuidance)
    }

    @Test func guidanceNeverCopiesSensitiveSessionMetadata() throws {
        let store = MonitorStore()
        var privateRow = row()
        privateRow["name"] = "Private project title /Users/private"
        store.receive(try data(packet(rows: [privateRow])), at: time(), epoch: 0)
        for health in [FeedHealth.monitoring, .unavailable, .invalid, .stale] {
            if health != .monitoring { store.fail(health) }
            let status = MonitoringStatus(store: store)
            let copy = [status.headline, status.detail, status.inventory, status.recovery ?? "", status.coverage].joined(separator: " ")
            #expect(!copy.contains("Private project"))
            #expect(!copy.contains("/Users/"))
            #expect(!copy.contains(store.sessions[0].id))
            #expect(status.coverage.contains("supported Codex sessions"))
        }
    }
}
