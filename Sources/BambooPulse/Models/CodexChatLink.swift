import CryptoKit
import Foundation

struct CodexChatLink: Equatable {
    let threadID: String
    let url: URL

    init?(_ text: String) {
        guard text.utf8.count <= 512 else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "codex://threads/"
        guard value.hasPrefix(prefix) else { return nil }
        let id = String(value.dropFirst(prefix.count))
        guard id.count == 36, let uuid = UUID(uuidString: id),
              uuid.uuidString.lowercased() == id, let url = URL(string: value) else { return nil }
        threadID = id
        self.url = url
    }

    var sessionID: String {
        SHA256.hash(data: Data(threadID.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
