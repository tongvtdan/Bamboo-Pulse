import AppKit
import PulseCore

@MainActor
final class SessionNavigationController {
    typealias OpenHandler = @MainActor (CodexChatLink, @escaping @MainActor (String?) -> Void) -> Void
    typealias GeminiOpenHandler = @MainActor (URL, @escaping @MainActor (String?) -> Void) -> Void
    typealias LookupHandler = @MainActor (String) async throws -> String?
    private let lookup: LookupHandler
    private let opener: OpenHandler
    private let geminiLookup: (String) -> Session?
    private let geminiOpener: GeminiOpenHandler
    private let clock: () -> MonitorTime
    private var opening = false

    init(lookup: @escaping LookupHandler = { try await CoordinatorFeed().chatThreadID(for: $0) },
         opener: @escaping OpenHandler = CodexChatOpener.open,
         geminiLookup: @escaping (String) -> Session? = { _ in nil },
         geminiOpener: @escaping GeminiOpenHandler = AntigravityChatOpener.open,
         clock: @escaping () -> MonitorTime = { .now }) {
        self.lookup = lookup
        self.opener = opener
        self.geminiOpener = geminiOpener
        self.geminiLookup = geminiLookup
        self.clock = clock
    }

    func activate(_ session: Session, synthetic: Bool) {
        guard !synthetic else { return }
        if session.isGemini {
            _ = openGemini(session, synthetic: synthetic)
            return
        }
        Task { [weak self] in
            do { try await self?.openChat(for: session.id, synthetic: synthetic) }
            catch { self?.presentError(error is SessionLinkError ? error.localizedDescription : SessionLinkError.unavailable.localizedDescription) }
        }
    }

    @discardableResult
    func openGemini(_ session: Session, synthetic: Bool) -> Bool {
        guard !synthetic, !opening, let current = geminiLookup(session.id), current.id == session.id,
              let url = current.geminiURL(at: clock()) else { return false }
        opening = true
        geminiOpener(url) { [weak self] message in
            self?.opening = false
            if let message { self?.presentError(message, provider: "Antigravity") }
        }
        return true
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

    private func presentError(_ message: String, provider: String = "Codex") {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Could not open " + provider + " conversation"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
