import AppKit
import PulseCore

@MainActor
final class SessionNavigationController {
    typealias OpenHandler = @MainActor (CodexChatLink, @escaping @MainActor (String?) -> Void) -> Void
    typealias LookupHandler = @MainActor (String) async throws -> String?
    private let lookup: LookupHandler
    private let opener: OpenHandler
    private var opening = false

    init(lookup: @escaping LookupHandler = { try await CoordinatorFeed().chatThreadID(for: $0) },
         opener: @escaping OpenHandler = CodexChatOpener.open) {
        self.lookup = lookup
        self.opener = opener
    }

    func activate(_ session: Session, synthetic: Bool) {
        guard !synthetic else { return }
        Task { [weak self] in
            do { try await self?.openChat(for: session.id, synthetic: synthetic) }
            catch { self?.presentError(error is SessionLinkError ? error.localizedDescription : SessionLinkError.unavailable.localizedDescription) }
        }
    }

    @discardableResult
    func openChat(for sessionID: String, synthetic: Bool) async throws -> Bool {
        guard !synthetic, !opening else { return false }
        opening = true
        defer { opening = false }
        let destination: String?
        do { destination = try await lookup(sessionID) }
        catch FeedError.unsupportedMethod { throw SessionLinkError.unsupported }
        guard let threadID = destination else { throw SessionLinkError.unavailable }
        try Task.checkCancellation()
        guard let link = CodexChatLink("codex://threads/" + threadID), link.sessionID == sessionID
        else { throw SessionLinkError.invalidTarget }
        opener(link) { [weak self] message in
            if let message { self?.presentError(message) }
        }
        return true
    }

    private func presentError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Could not open Codex chat"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
