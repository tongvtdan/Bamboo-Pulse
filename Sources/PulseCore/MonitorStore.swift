import Foundation
import Observation

@MainActor @Observable
public final class MonitorStore {
    private var codexSessions: [Session] = []
    private var geminiSessions: [Session] = []
    @ObservationIgnored private var geminiEvents: [String: GeminiHook] = [:]
    @ObservationIgnored private var latestGeminiClock: MonitorTime?
    @ObservationIgnored private var nextGeminiChange = Double.infinity
    public var sessions: [Session] { codexSessions + geminiSessions }
    public var displayHealth: FeedHealth { geminiSessions.isEmpty ? health : .monitoring }

    @discardableResult public func updateGemini(_ incoming: [GeminiHook], at time: MonitorTime) -> [String] {
        guard !isSynthetic else { return [] }
        if let previous = latestGeminiClock, time.wallMS < previous.wallMS ||
            abs((time.wallMS - previous.wallMS) - (time.continuousMS - previous.continuousMS)) > 2500 {
            resetGemini()
        }
        latestGeminiClock = time
        guard !incoming.isEmpty || time.wallMS >= nextGeminiChange else { return [] }
        var requests = Set<String>()
        geminiEvents = geminiEvents.filter { (0..<120000).contains(time.wallMS - $0.value.observed) }
        for event in incoming {
            let age = time.wallMS - event.observed
            let previous = geminiEvents[event.id]
            guard event.valid, (0..<2500).contains(age),
                  event.observed > 0, event.observed >= (previous?.observed ?? 0),
                  previous != nil || geminiEvents.count < 128 else { continue }
            if let previous, event.observed == previous.observed {
                // No sequence number distinguishes conflicting CLI events at the same millisecond.
                if event.id.hasPrefix("cli-"), event.state != previous.state {
                    geminiEvents[event.id] = GeminiHook(id: event.id, state: .unknown, observed: event.observed)
                }
                continue
            }
            if event.state != .unknown || previous != nil {
                if event.state == .needsAttention {
                    requests.insert("gemini:" + event.id)
                }
                geminiEvents[event.id] = event
            }
        }
        nextGeminiChange = .infinity
        let rows = geminiEvents.values.sorted { $0.id < $1.id }.map { event in
            let age = time.wallMS - event.observed
            let cli = event.id.hasPrefix("cli-")
            let alias = String((cli ? event.id.dropFirst(4) : event.id[...]).prefix(8))
            let fresh = age < 30000 && event.state != .unknown
            nextGeminiChange = min(nextGeminiChange, event.observed + (fresh ? 30000 : 120000))
            let timing = fresh ? StatusTiming(startedContinuousMS: time.continuousMS - age,
                                              validUntilContinuousMS: time.continuousMS - age + 30000,
                                              isLowerBound: false) : nil
            return Session(id: "gemini:" + event.id, alias: alias, name: (cli ? "Gemini CLI " : "Gemini chat ") + alias,
                           state: fresh ? event.state : .unknown, ageMS: age,
                           remainingMS: max(0, 30000 - age), statusTiming: timing,
                           observationContinuity: cli && fresh ? event.observed.bitPattern : nil)
        }
        if rows != geminiSessions { geminiSessions = rows }
        return rows.filter { requests.contains($0.id) && $0.state == .needsAttention }.map(\.id)
    }

    public func resetGemini() {
        geminiEvents.removeAll()
        geminiSessions = []
        latestGeminiClock = nil
        nextGeminiChange = .infinity
    }
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
            codexSessions = [
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
        if displayHealth != .monitoring && displayHealth != .synthetic { return "Status unknown" }
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
                codexSessions = codexSessions.map { row in
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
                codexSessions = []
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
        codexSessions = codexSessions.map { $0.displaying(.unknown) }
    }

    public func refresh(at time: MonitorTime) {
        guard !isSynthetic, let source = packet, let receipt else { return }
        guard validClock(time) else { fail(.stale); return }
        lastTime = time
        ageFloor = max(ageFloor, time.wallMS - source.timestampMS,
                       time.continuousMS - receipt.continuousMS + receipt.wallMS - source.timestampMS)
        guard ageFloor < source.validForMS else { fail(.stale); return }
        let previous = Dictionary(uniqueKeysWithValues: codexSessions.map { ($0.id, $0) })
        codexSessions = source.sessions.map { row in
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
