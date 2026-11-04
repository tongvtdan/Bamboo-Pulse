import Foundation
import PulseCore

func row(_ state: String = "WORKING", id: String = String(repeating: "a", count: 32), alias: String = "CX1", remaining: Int = 1000) -> [String: Any] {
    ["id": id, "alias": alias, "name": "Build", "state": state, "age_ms": 0, "remaining_ms": remaining]
}

func packet(sequence: Int = 1, timestamp: Int = 100000, validity: Int = 2000,
            generation: String = String(repeating: "b", count: 32), rows: [[String: Any]] = [row()]) -> [String: Any] {
    ["version": 1, "generation": generation, "sequence": sequence,
     "timestamp_ms": timestamp, "valid_for_ms": validity, "monitoring_available": true,
     "sessions": rows, "bar": NSNull()]
}

func data(_ packet: [String: Any] = packet()) throws -> Data {
    try JSONSerialization.data(withJSONObject: packet)
}

func time(_ delta: Double = 0) -> MonitorTime { MonitorTime(wallMS: 100000 + delta, continuousMS: 500 + delta) }

actor CountingFeed: NowFeed {
    private(set) var reads = 0
    func read() async throws -> Data {
        reads += 1
        return try data(packet(sequence: reads, timestamp: Int(MonitorTime.now.wallMS)))
    }
}

actor SuspendedFeed: NowFeed {
    private(set) var reads = 0
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    func read() async throws -> Data {
        reads += 1
        let index = reads
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func complete(_ index: Int, with bytes: Data) { pending.removeValue(forKey: index)?.resume(returning: bytes) }
    func fail(_ index: Int, with error: FeedError) { pending.removeValue(forKey: index)?.resume(throwing: error) }
}
