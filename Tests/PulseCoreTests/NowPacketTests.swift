import Foundation
import Testing
@testable import PulseCore

struct NowPacketTests {
    @Test func malformedEnvelopeHasAnExplicitInvalidDataReason() {
        do {
            _ = try CoordinatorFeed.decodeResponse(Data("not JSON\n".utf8), identifier: "request")
            Issue.record("Malformed envelope was accepted")
        } catch FeedError.invalidData {
            // Driver uses this reason to distinguish rejection from unavailable transport.
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test(arguments: SessionState.allCases)
    func mapsOnlyObservedStates(_ state: SessionState) throws {
        let parsed = try NowPacket.parse(data(packet(rows: [row(state.rawValue)])))
        #expect(parsed.sessions.first?.state == state)
        #expect(state.label != "Success")
        if state == .turnEnded { #expect(state.label == "Turn ended") }
    }

    @Test func keepsSameProviderSessionsDistinct() throws {
        let rows = [row(), row("NEEDS_ATTENTION", id: String(repeating: "c", count: 32), alias: "CX2")]
        let parsed = try NowPacket.parse(data(packet(rows: rows)))
        #expect(parsed.sessions.count == 2)
        #expect(Set(parsed.sessions.map(\.id)).count == 2)
        #expect(parsed.sessions.allSatisfy { $0.provider == "Codex" })
    }

    @Test func rejectsUnsupportedAndMalformedMetadata() throws {
        var cases: [[String: Any]] = []
        for (key, value) in [("version", 2 as Any), ("version", true), ("sequence", true),
                             ("sequence", 0), ("sequence", 1.5), ("valid_for_ms", 2501),
                             ("valid_for_ms", 0), ("timestamp_ms", -1), ("monitoring_available", 1),
                             ("generation", "wrong"), ("provider", "Claude")] {
            var raw = packet(); raw[key] = value; cases.append(raw)
        }
        for raw in cases { #expect(throws: (any Error).self) { try NowPacket.parse(data(raw)) } }
        #expect(throws: (any Error).self) { try NowPacket.parse(Data("{".utf8)) }
        #expect(throws: (any Error).self) { try NowPacket.parse(Data(repeating: 32, count: 131073)) }
    }

    @Test func rejectsInvalidSessions() throws {
        for (key, value) in [("state", "IDLE" as Any), ("state", "SUCCESS"), ("alias", "CX0"),
                             ("alias", "CL1"), ("remaining_ms", -1), ("age_ms", 120001),
                             ("name", " "), ("name", "test\u{202e}"), ("name", String(repeating: "a", count: 161))] {
            var session = row(); session[key] = value
            #expect(throws: (any Error).self) { try NowPacket.parse(data(packet(rows: [session]))) }
        }
        #expect(throws: (any Error).self) { try NowPacket.parse(data(packet(rows: [row(), row()]))) }
        #expect(throws: (any Error).self) { try NowPacket.parse(data(packet(rows: [row("NEEDS_ATTENTION", remaining: 5001)]))) }
        #expect(throws: (any Error).self) { try NowPacket.parse(data(packet(rows: Array(repeating: row(), count: 129)))) }
        var unnamed = row(); unnamed["name"] = NSNull()
        #expect(try NowPacket.parse(data(packet(rows: [unnamed]))).sessions[0].title == "Name unavailable")
    }

    @Test func rejectsDuplicateKeysIncludingEscapedKeys() throws {
        let valid = String(decoding: try data(), as: UTF8.self)
        for prefix in ["\"version\":1,", "\"\\u0076ersion\":1,"] {
            let duplicate = "{" + prefix + valid.dropFirst()
            #expect(throws: (any Error).self) { try NowPacket.parse(Data(duplicate.utf8)) }
        }
        let envelope = "{\"id\":\"wrong\",\"id\":\"right\",\"result\":" + valid + "}\n"
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeResponse(Data(envelope.utf8), identifier: "right") }
    }

    @Test func validatesUnusedBarInsteadOfTrustingPartialPacket() throws {
        var raw = packet()
        let validBar: [String: Any] = ["serial": "012345abcdef", "connection_id": String(repeating: "c", count: 32),
            "state": "WORKING", "remaining_ms": 500, "contributors": [String(repeating: "a", count: 32)], "delivery": "UNCONFIRMED"]
        raw["bar"] = validBar
        #expect(throws: Never.self) { try NowPacket.parse(data(raw)) }
        for (key, value) in [("delivery", "CONFIRMED" as Any), ("contributors", ["missing"]), ("serial", "invalid")] {
            var bar = validBar; bar[key] = value; raw["bar"] = bar
            #expect(throws: (any Error).self) { try NowPacket.parse(data(raw)) }
        }
        raw = packet(); raw["monitoring_available"] = false
        #expect(throws: (any Error).self) { try NowPacket.parse(data(raw)) }
        raw["sessions"] = []
        #expect(try NowPacket.parse(data(raw)).monitoringAvailable == false)
    }

    @Test func boundsAndMatchesResponseEnvelope() throws {
        let framed = try JSONSerialization.data(withJSONObject: ["id": "request-1", "result": packet()]) + Data([10])
        #expect(try CoordinatorFeed.decodeResponse(Data(framed.prefix(20)), identifier: "request-1") == nil)
        #expect(try CoordinatorFeed.decodeResponse(framed, identifier: "request-1") != nil)
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeResponse(framed, identifier: "other") }
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeResponse(framed + Data([10]), identifier: "request-1") }
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeResponse(Data(repeating: 1, count: 131073), identifier: "request-1") }
        let rejected = try JSONSerialization.data(withJSONObject: ["id": "request-1", "result": ["state": "REJECTED"]]) + Data([10])
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeResponse(rejected, identifier: "request-1") }
    }

    @Test func validatesNavigationBindingAndUnavailableWithoutChangingStatusSchema() throws {
        let sessionID = "bd7662a5eeb41614e720d477abfcb227"
        let target: [String: Any] = ["version": 1, "session_id": sessionID, "thread_id": "11111111-1111-4111-8111-111111111111"]
        func frame(_ result: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["id": "req", "result": result]) + Data([10])
        }
        #expect(try CoordinatorFeed.decodeChatLinkResponse(frame(target), identifier: "req", sessionID: sessionID) != nil)
        var absent = target; absent["thread_id"] = NSNull()
        #expect(try CoordinatorFeed.decodeChatLinkResponse(frame(absent), identifier: "req", sessionID: sessionID) != nil)
        for (key, value) in [("version", true as Any), ("version", 2), ("session_id", String(repeating: "b", count: 32)),
                             ("thread_id", "22222222-2222-4222-8222-222222222222"), ("thread_id", "codex://threads/new"),
                             ("thread_id", String(repeating: "x", count: 513)), ("extra", "value")] {
            var bad = target; bad[key] = value
            #expect(throws: (any Error).self) { try CoordinatorFeed.decodeChatLinkResponse(frame(bad), identifier: "req", sessionID: sessionID) }
        }
        let legacy: [String: Any] = ["state": "REJECTED", "reason": "METHOD_NOT_ALLOWED"]
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeChatLinkResponse(frame(legacy), identifier: "req", sessionID: sessionID) }
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeChatLinkResponse(frame(target), identifier: "other", sessionID: sessionID) }
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeChatLinkResponse(frame(target) + Data([10]), identifier: "req", sessionID: sessionID) }
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeChatLinkResponse(Data(repeating: 32, count: 131073), identifier: "req", sessionID: sessionID) }
        let duplicate = Data(("{\"id\":\"req\",\"result\":{\"version\":1,\"version\":1,\"session_id\":\"" + sessionID + "\",\"thread_id\":null}}\n").utf8)
        #expect(throws: (any Error).self) { try CoordinatorFeed.decodeChatLinkResponse(duplicate, identifier: "req", sessionID: sessionID) }
    }

    @Test func unsupportedNavigationRequiresAnExactBoundRejectionAndNeverChangesStatusParsing() throws {
        let sessionID = "bd7662a5eeb41614e720d477abfcb227";
        let rejection = ["state": "REJECTED", "reason": "METHOD_NOT_ALLOWED"]
        func frame(_ result: [String: Any], id: String = "req") throws -> Data {
            try JSONSerialization.data(withJSONObject: ["id": id, "result": result]) + Data([10])
        }
        let bytes = try frame(rejection)
        do {
            _ = try CoordinatorFeed.decodeChatLinkResponse(bytes, identifier: "req", sessionID: sessionID)
            Issue.record("An unsupported method was accepted as a navigation target")
        } catch FeedError.unsupportedMethod { }

        for bad in [try frame(rejection, id: "other"),
                    try frame(["state": "REJECTED", "reason": "METHOD_NOT_ALLOWED", "extra": true]),
                    try frame(["state": "ACCEPTED", "reason": "METHOD_NOT_ALLOWED"]),
                    try frame(["state": "REJECTED", "reason": "MALFORMED"]), bytes + Data([10]),
                    Data("{\"id\":\"req\",\"result\":{\"state\":\"REJECTED\",\"state\":\"REJECTED\",\"reason\":\"METHOD_NOT_ALLOWED\"}}\n".utf8)] {
            do {
                _ = try CoordinatorFeed.decodeChatLinkResponse(bad, identifier: "req", sessionID: sessionID)
                Issue.record("Malformed or unbound method rejection was accepted")
            } catch FeedError.invalidData { }
        }
        do {
            _ = try CoordinatorFeed.decodeResponse(bytes, identifier: "req")
            Issue.record("Status parsing accepted a method rejection")
        } catch FeedError.invalidData { }
    }

    @Test func missingSocketIsUnavailable() async {
        let feed = CoordinatorFeed(path: "/tmp/bamboo-pulse-missing-\(UUID().uuidString)/coordinator.sock")
        await #expect(throws: (any Error).self) { try await feed.read() }
    }
}
