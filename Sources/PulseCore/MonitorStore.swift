import Foundation
import Observation

@MainActor @Observable
public final class MonitorStore {
    public private(set) var sessions: [Session] = []
    public private(set) var health: FeedHealth
    public let isSynthetic: Bool
    public private(set) var epoch: UInt64 = 0
    @ObservationIgnored private var packet: NowPacket?
    @ObservationIgnored private var generation: String?
    @ObservationIgnored private var sequence: Double = 0
    @ObservationIgnored private var timestampFloor: Double = 0
    @ObservationIgnored private var retired = Set<String>()
    @ObservationIgnored private var receipt: MonitorTime?
    @ObservationIgnored private var lastTime: MonitorTime?
    @ObservationIgnored private var ageFloor: Double = 0
    @ObservationIgnored private var continuitySequence: UInt64 = 0

    public init(synthetic: Bool = false) {
        isSynthetic = synthetic
        health = synthetic ? .synthetic : .connecting
        if synthetic {
            sessions = [
                Session(id: "sample-1", alias: "CX1", name: "Configuration", state: .needsAttention, ageMS: 0, remainingMS: 0),
                Session(id: "sample-2", alias: "CX2", name: "Build", state: .working, ageMS: 0, remainingMS: 0),
                Session(id: "sample-3", alias: "CX3", name: "Documentation", state: .turnEnded, ageMS: 0, remainingMS: 0),
                Session(id: "sample-4", alias: "CX4", name: "Review", state: .unknown, ageMS: 0, remainingMS: 0),
            ]
        }
    }

    public var attentionCount: Int { sessions.filter { $0.state == .needsAttention }.count }
    public var observationGeneration: String? { generation }
    public var workingCount: Int { sessions.filter { $0.state == .working }.count }
    public var summary: String {
        if health != .monitoring && health != .synthetic { return "Status unknown" }
        if sessions.isEmpty { return "No sessions observed" }
        return "\(attentionCount) needs you · \(workingCount) working"
    }

    /// A lifecycle boundary retires in-flight responses without resetting ordering floors.
    @discardableResult public func beginEpoch() -> UInt64 {
        precondition(epoch < .max, "Monitor lifecycle exhausted")
        epoch += 1
        if !isSynthetic { fail(.unavailable) }
        return epoch
    }

    public func receive(_ data: Data, at time: MonitorTime, epoch expected: UInt64) {
        guard !isSynthetic, epoch == expected else { return }
        do {
            let next = try NowPacket.parse(data)
            guard validClock(time), next.timestampMS <= time.wallMS,
                  time.wallMS - next.timestampMS < next.validForMS else { throw FeedError.stale }
            guard !retired.contains(next.generation), next.timestampMS >= timestampFloor,
                  next.generation != generation || next.sequence > sequence else { throw FeedError.outOfOrder }
            // Retire an expired prior lease even if its regular expiry tick was delayed.
            refresh(at: time)
            if let old = generation, old != next.generation {
                guard retired.count < 32 else { throw FeedError.outOfOrder }
                retired.insert(old)
                sessions = sessions.map { row in
                    var baseline = row
                    baseline.statusTiming = nil
                    baseline.observationContinuity = nil
                    return baseline
                }
            }
            generation = next.generation
            sequence = next.sequence
            timestampFloor = next.timestampMS
            packet = next
            receipt = time
            lastTime = time
            ageFloor = time.wallMS - next.timestampMS
            if next.monitoringAvailable {
                health = .monitoring
                refresh(at: time)
            } else {
                sessions = []
                fail(.unavailable)
            }
        } catch FeedError.stale { fail(.stale) }
        catch { fail(.invalid) }
    }

    public func fail(_ reason: FeedHealth, epoch expected: UInt64? = nil) {
        guard !isSynthetic, expected == nil || expected == epoch else { return }
        health = reason
        packet = nil
        receipt = nil
        sessions = sessions.map { $0.displaying(.unknown) }
    }

    public func refresh(at time: MonitorTime) {
        guard !isSynthetic, let source = packet, let receipt else { return }
        guard validClock(time) else { fail(.stale); return }
        lastTime = time
        ageFloor = max(ageFloor, time.wallMS - source.timestampMS,
                       time.continuousMS - receipt.continuousMS + receipt.wallMS - source.timestampMS)
        guard ageFloor < source.validForMS else { fail(.stale); return }
        let previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        sessions = source.sessions.map { row in
            var displayed = row.displaying(ageFloor < row.remainingMS ? row.state : .unknown)
            guard displayed.state != .unknown else { return displayed }
            let prior = previous[row.id]
            displayed.observationContinuity = prior?.observationContinuity ?? nextContinuity()
            let continuing = prior?.state == displayed.state ? prior?.statusTiming : nil
            displayed.statusTiming = StatusTiming(
                startedContinuousMS: continuing?.startedContinuousMS ?? time.continuousMS,
                validUntilContinuousMS: time.continuousMS + min(source.validForMS, row.remainingMS) - ageFloor,
                isLowerBound: continuing?.isLowerBound ?? (prior?.statusTiming == nil))
            return displayed
        }
    }

    private func nextContinuity() -> UInt64 {
        precondition(continuitySequence < .max, "Observation continuity exhausted")
        continuitySequence += 1
        return continuitySequence
    }

    private func validClock(_ time: MonitorTime) -> Bool {
        guard time.wallMS.isFinite, time.continuousMS.isFinite else { return false }
        guard let previous = lastTime else { return true }
        return time.wallMS >= previous.wallMS && time.continuousMS >= previous.continuousMS
    }
}
