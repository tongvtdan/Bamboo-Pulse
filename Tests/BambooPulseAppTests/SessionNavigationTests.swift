import AppKit
import PulseCore
import Testing

@Suite("Chat opening and keyboard commands") @MainActor
struct SessionNavigationTests {
    @Test func unsupportedSetupExplainsDirectOpeningWithoutFutileRetriesOrOpeningAnything() async throws {
        let id = "bd7662a5eeb41614e720d477abfcb227"
        let rejection = try JSONSerialization.data(withJSONObject: ["id": "req",
            "result": ["state": "REJECTED", "reason": "METHOD_NOT_ALLOWED"]]) + Data([10])
        var opens = 0
        let navigation = SessionNavigationController(lookup: { selected in
            _ = try CoordinatorFeed.decodeChatLinkResponse(rejection, identifier: "req", sessionID: selected)
            return nil
        }) { _, _ in opens += 1 }
        do {
            _ = try await navigation.openChat(for: id, synthetic: false)
            Issue.record("Unsupported setup unexpectedly opened a chat")
        } catch SessionLinkError.unsupported {
            let message = SessionLinkError.unsupported.localizedDescription
            #expect(message.contains("doesn’t support direct opening"))
            #expect(message.contains("Open the chat in Codex"))
            #expect(!message.contains("try again"))
        }
        #expect(opens == 0)
        #expect(!(try await navigation.openChat(for: id, synthetic: true)))
    }

    @Test func opensExactObservedTargetsWithoutSavedLinksAndNeverPreview() async throws {
        let first = CodexChatLink("codex://threads/11111111-1111-4111-8111-111111111111")!
        let second = CodexChatLink("codex://threads/22222222-2222-4222-8222-222222222222")!
        let targets = [first.sessionID: first.threadID, second.sessionID: second.threadID]
        var opened: [CodexChatLink] = [], lookedUp: [String] = []
        let navigation = SessionNavigationController(lookup: { id in
            lookedUp.append(id)
            return targets[id]
        }) { link, completion in opened.append(link); completion(nil) }
        #expect(try await navigation.openChat(for: second.sessionID, synthetic: false))
        #expect(try await navigation.openChat(for: first.sessionID, synthetic: false))
        #expect(opened == [second, first])
        #expect(!(try await navigation.openChat(for: first.sessionID, synthetic: true)))
        #expect(lookedUp == [second.sessionID, first.sessionID])
        await #expect(throws: SessionLinkError.self) { try await navigation.openChat(for: "missing", synthetic: false) }
        #expect(opened == [second, first])
    }

    @Test func mismatchedAndMalformedTargetsNeverOpen() async {
        for target in ["22222222-2222-4222-8222-222222222222", "11111111-1111-4111-8111-111111111111?prompt=run"] {
            var opens = 0
            let navigation = SessionNavigationController(lookup: { _ in target }) { _, _ in opens += 1 }
            await #expect(throws: SessionLinkError.self) {
                try await navigation.openChat(for: "bd7662a5eeb41614e720d477abfcb227", synthetic: false)
            }
            #expect(opens == 0)
        }
    }

    @Test func repeatedClicksDoNotQueueMoreLookupsOrOpens() async throws {
        let first = CodexChatLink("codex://threads/11111111-1111-4111-8111-111111111111")!
        var pending: CheckedContinuation<String?, Never>?
        var opens = 0
        let navigation = SessionNavigationController(lookup: { _ in
            await withCheckedContinuation { pending = $0 }
        }) { _, completion in opens += 1; completion(nil) }
        let task = Task { try await navigation.openChat(for: first.sessionID, synthetic: false) }
        while pending == nil { await Task.yield() }
        #expect(!(try await navigation.openChat(for: first.sessionID, synthetic: false)))
        pending?.resume(returning: first.threadID)
        #expect(try await task.value)
        #expect(opens == 1)
    }

    @Test func appCommandsKeepSettingsAndQuitWithoutACloseShortcut() {
        var settingsOpened = 0
        let controller = PulseApplicationMenu { settingsOpened += 1 }
        let app = controller.menu.item(at: 0)!.submenu!
        let settings = app.item(at: 0)!, quit = app.items.last!
        #expect(settings.keyEquivalent == ",")
        #expect(settings.keyEquivalentModifierMask.contains(.command))
        app.performActionForItem(at: 0)
        #expect(settingsOpened == 1)
        #expect(quit.keyEquivalent == "q")
        #expect(quit.action == #selector(NSApplication.terminate(_:)))
        let close = controller.menu.item(at: 1)!.submenu!.item(at: 0)!
        #expect(close.keyEquivalent.isEmpty)
        #expect(close.action == #selector(NSWindow.performClose(_:)))
        let commandW = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: 0, context: nil, characters: "w",
            charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
        #expect(!controller.menu.performKeyEquivalent(with: commandW))
    }
}
