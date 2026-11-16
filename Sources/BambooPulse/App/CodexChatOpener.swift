import AppKit

@MainActor
enum CodexChatOpener {
    static func open(_ link: CodexChatLink, completion: @escaping @MainActor (String?) -> Void) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            completion("Codex is not installed or registered on this Mac. Open Codex once, then try again.")
            return
        }
        NSWorkspace.shared.open([link.url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in completion(message) }
        }
    }
}

@MainActor
enum AntigravityChatOpener {
    static func open(_ url: URL, completion: @escaping @MainActor (String?) -> Void) {
        guard url.scheme == "antigravity-ide", url.host == "google.google-antigravity",
              url.path == "/open-conversation",
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.antigravity-ide") else {
            completion("Antigravity IDE is not installed or registered on this Mac. Open it once, then try again.")
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            let message = error?.localizedDescription
            Task { @MainActor in completion(message) }
        }
    }
}
