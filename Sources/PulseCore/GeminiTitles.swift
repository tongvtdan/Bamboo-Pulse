import Foundation
import SQLite3

/// Read display metadata only for IDE destinations admitted by the monitor.
struct GeminiTitles {
    let database: URL

    func lookup(_ destinations: [GeminiDestination]) -> [String: String] {
        guard !destinations.isEmpty else { return [:] }
        var connection: OpaquePointer?
        let status = sqlite3_open_v2(database.path, &connection, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(connection) }
        guard status == SQLITE_OK else { return [:] }
        var statement: OpaquePointer?
        let query = "SELECT substr(title, 1, 256) FROM conversation_summaries WHERE conversation_id = ?"
        guard sqlite3_prepare_v2(connection, query, -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }

        var titles: [String: String] = [:]
        for destination in destinations {
            sqlite3_reset(statement)
            let title: String? = destination.conversationID.withCString { id in
                guard sqlite3_bind_text(statement, 1, id, -1, nil) == SQLITE_OK else { return nil }
                defer { sqlite3_clear_bindings(statement) }
                guard sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0)
                else { return nil }
                return String(cString: value).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            }
            if let title, !title.isEmpty { titles[destination.conversationID] = title }
        }
        return titles
    }
}
