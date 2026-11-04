import Foundation

enum SessionLinkError: LocalizedError {
    case unavailable, invalidTarget, unsupported

    var errorDescription: String? {
        switch self {
        case .unavailable: "Pulse can’t open this chat yet. Open it directly in Codex and try again after its status updates."
        case .invalidTarget: "Pulse couldn’t confirm which chat to open. Try again after the session updates."
        case .unsupported: "This setup doesn’t support direct opening yet. Open the chat in Codex."
        }
    }
}
