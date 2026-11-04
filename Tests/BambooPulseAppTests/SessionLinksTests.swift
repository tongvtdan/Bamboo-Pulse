import Foundation
import Testing

@Suite("Verified local chat links") @MainActor
struct SessionLinksTests {
    private let first = "codex://threads/11111111-1111-4111-8111-111111111111"

    @Test func canonicalLinkKeepsExactURLAndHashesOnlyTechnicalID() {
        let link = CodexChatLink(first)!
        #expect(link.url.absoluteString == first)
        #expect(link.threadID == "11111111-1111-4111-8111-111111111111")
        #expect(link.sessionID == "bd7662a5eeb41614e720d477abfcb227")
        #expect(CodexChatLink(" \n\(first)\n") == link)
    }

    @Test(arguments: [
        "https://example.com/chat", "file:///tmp/a", "javascript:alert(1)",
        "codex://threads/new", "codex://settings", "codex://new?prompt=run",
        "codex://threads/11111111-1111-4111-8111-111111111111?prompt=run",
        "codex://threads/11111111-1111-4111-8111-111111111111#extra",
        "codex://threads/11111111-1111-4111-8111-111111111111/extra",
        "codex://other/11111111-1111-4111-8111-111111111111",
        "codex://user@threads/11111111-1111-4111-8111-111111111111",
        "codex://threads:80/11111111-1111-4111-8111-111111111111",
        "codex://threads/%31%31%31%31%31%31%31%31-1111-4111-8111-111111111111",
        "codex://threads/AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "codex://threads/not-an-id",
        "codex://threads/11111111111141118111111111111111", String(repeating: "x", count: 513)
    ])
    func allOtherActionsAndMalformedLinksAreRejected(_ value: String) {
        #expect(CodexChatLink(value) == nil)
    }

}
