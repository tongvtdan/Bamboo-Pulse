import Foundation
import CoreFoundation

/// Existing coordinator v1 schema. No provider inference beyond its Codex-only contract.
public struct NowPacket: Sendable {
    public let generation: String
    public let sequence: Double
    public let timestampMS: Double
    public let validForMS: Double
    public let monitoringAvailable: Bool
    public let sessions: [Session]

    public static func parse(_ data: Data) throws -> NowPacket {
        guard data.count <= 131072 else { throw FeedError.invalidData }
        let raw = try StrictJSON.object(data)
        let object = try exact(raw, "version,generation,sequence,timestamp_ms,valid_for_ms,monitoring_available,sessions,bar")
        guard try number(object["version"], max: 1) == 1,
              let available = object["monitoring_available"] as? NSNumber,
              CFGetTypeID(available) == CFBooleanGetTypeID(),
              let rows = object["sessions"] as? [Any], rows.count <= 128 else { throw FeedError.invalidData }
        let generation = try hex(object["generation"], length: 32)
        let sequence = try number(object["sequence"])
        let timestamp = try number(object["timestamp_ms"], max: 8640000000000000)
        let validity = try number(object["valid_for_ms"], max: 2500)
        guard sequence > 0, validity > 0 else { throw FeedError.invalidData }
        var ids = Set<String>(), aliases = Set<String>(), sessions: [Session] = []
        for raw in rows {
            let row = try exact(raw, "id,alias,name,state,age_ms,remaining_ms")
            let id = try hex(row["id"], length: 32)
            guard ids.insert(id).inserted,
                  let alias = row["alias"] as? String,
                  alias.range(of: "^CX[1-9][0-9]{0,3}$", options: .regularExpression) != nil,
                  aliases.insert(alias).inserted,
                  let rawState = row["state"] as? String,
                  let state = SessionState(rawValue: rawState) else { throw FeedError.invalidData }
            let name: String?
            if row["name"] is NSNull { name = nil }
            else {
                guard let value = row["name"] as? String,
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      value.utf8.count <= 160,
                      !value.unicodeScalars.contains(where: { [.control, .format, .surrogate, .privateUse, .unassigned].contains($0.properties.generalCategory) })
                else { throw FeedError.invalidData }
                name = value
            }
            sessions.append(Session(id: id, alias: alias, name: name, state: state,
                ageMS: try number(row["age_ms"], max: 120000),
                remainingMS: try number(row["remaining_ms"], max: state == .needsAttention ? 5000 : 120000)))
        }
        if !(object["bar"] is NSNull) {
            let bar = try exact(object["bar"], "serial,connection_id,state,remaining_ms,contributors,delivery")
            _ = try hex(bar["serial"], length: 12)
            _ = try hex(bar["connection_id"], length: 32)
            _ = try number(bar["remaining_ms"], max: 120000)
            guard let state = bar["state"] as? String, SessionState(rawValue: state) != nil,
                  bar["delivery"] as? String == "UNCONFIRMED",
                  let contributors = bar["contributors"] as? [String], contributors.count <= 128,
                  Set(contributors).count == contributors.count, contributors.allSatisfy(ids.contains)
            else { throw FeedError.invalidData }
        }
        guard available.boolValue || (sessions.isEmpty && object["bar"] is NSNull) else { throw FeedError.invalidData }
        return NowPacket(generation: generation, sequence: sequence, timestampMS: timestamp,
                         validForMS: validity, monitoringAvailable: available.boolValue, sessions: sessions)
    }

    private static func exact(_ raw: Any?, _ keys: String) throws -> [String: Any] {
        guard let value = raw as? [String: Any], Set(value.keys) == Set(keys.components(separatedBy: ","))
        else { throw FeedError.invalidData }
        return value
    }

    private static func number(_ raw: Any?, max: Double = 9007199254740991) throws -> Double {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { throw FeedError.invalidData }
        let number = value.doubleValue
        guard number.isFinite, number >= 0, number <= max, number.rounded(.down) == number else { throw FeedError.invalidData }
        return number
    }

    private static func hex(_ raw: Any?, length: Int) throws -> String {
        guard let value = raw as? String, value.utf8.count == length,
              value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw FeedError.invalidData }
        return value
    }
}
