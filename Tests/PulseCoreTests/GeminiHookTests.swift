import Foundation
import Testing
@testable import PulseCore

struct GeminiHookTests {
    let chat = "00000000-0000-4000-8000-000000000001"
    let home = "/Users/test"

    func event(_ hook: String, model: String = "gemini-4-hydrogen-medium", host: String = "antigravity-ide",
               chatID: String? = nil, workspace: String = "/fixture", file: String = "transcript.jsonl", idle: Any = true, at time: Double = 1000) throws -> GeminiHook? {
        let id = chatID ?? chat
        let raw: [String: Any] = ["modelName": model, "conversationId": id, "fullyIdle": idle,
            "workspacePaths": [workspace], "lastUserInput": "private fixture",
            "transcriptPath": home + "/.gemini/" + host + "/brain/" + id + "/.system_generated/logs/" + file]
        return GeminiHook.project(try JSONSerialization.data(withJSONObject: raw), event: hook, workspace: "/fixture", home: home, now: time)
    }

    @Test func requiresModelHostAndExplicitFinalIdle() throws {
        #expect(try event("PreInvocation")?.state == .working)
        #expect(try event("Stop")?.state == .turnEnded)
        #expect(try event("Stop", idle: false)?.state == .unknown)
        #expect(try event("Stop", idle: 1)?.state == .unknown)
        #expect(try event("PreInvocation", host: "antigravity", file: "transcript_full.jsonl")?.state == .working)
        #expect(try event("PreInvocation", workspace: "/other") == nil)
        #expect(try event("PreToolUse") == nil)
        #expect(try event("PreInvocation", host: "antigravity-cli") == nil)
        #expect(try event("PreInvocation", host: "antigravity") == nil)
        #expect(try event("PreInvocation", chatID: "invalid") == nil)
        #expect(try event("PreInvocation", model: "claude-opus")?.state == .unknown)
    }

    @MainActor @Test func liveRowsAgeAndRecoverIndependentlyOfCodex() throws {
        let store = MonitorStore()
        let working = try #require(try event("PreInvocation"))
        func update(_ events: [GeminiHook], _ now: Double) {
            store.updateGemini(events, at: MonitorTime(wallMS: now, continuousMS: now))
        }
        update([working], 1000)
        let id = try #require(store.sessions.first?.id)
        #expect(store.sessions.first?.provider == "Gemini")
        store.fail(.unavailable)
        #expect(store.sessions.first?.state == .working)
        update([], 31000)
        #expect(store.sessions.first?.state == .unknown)
        update([try #require(try event("Stop", at: 32000))], 32000)
        #expect(store.sessions.first?.state == .turnEnded)
        #expect(store.sessions.first?.id == id)
        update([working], 32100)
        #expect(store.sessions.first?.state == .turnEnded)
        update([try #require(try event("PreInvocation", model: "claude", at: 33000))], 33000)
        #expect(store.sessions.first?.state == .unknown)
        update([], 153000)
        #expect(store.sessions.isEmpty)
    }

    @MainActor @Test func concurrentChatsAndOtherModels() throws {
        let store = MonitorStore()
        let time = MonitorTime(wallMS: 1000, continuousMS: 1000)
        store.updateGemini([try #require(try event("PreInvocation", model: "claude"))], at: time)
        #expect(store.sessions.isEmpty)
        let events = [try #require(try event("PreInvocation")), try #require(try event("Stop", chatID: UUID().uuidString.lowercased()))]
        store.updateGemini(events, at: time)
        #expect(Set(store.sessions.map(\.id)).count == 2)
        #expect(store.workingCount == 1)
        #expect(store.attentionCount == 0)
        let preview = MonitorStore(synthetic: true)
        preview.updateGemini(events, at: time)
        #expect(preview.sessions.allSatisfy { !$0.isGemini })
    }

    @Test func privateSocketTransportsOnlyProjectedFields() throws {
        let directory = "/private/tmp/gemini-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let socket = try #require(GeminiHookSocket(directory: directory))
        #expect(GeminiHookSocket(directory: directory) == nil)
        let working = try #require(try event("PreInvocation"))
        let raw = try JSONEncoder().encode(working)
        #expect(Set((try JSONSerialization.jsonObject(with: raw) as? [String: Any])!.keys) == ["id", "state", "observed"])
        GeminiHookSocket.send(working, directory: directory)
        #expect(socket.drain() == [working])
    }

    @MainActor @Test func cliEventsUseSourceTimeAndRejectUnrelatedAlerts() throws {
        func hook(_ event: String, type: String = "ToolPermission", stamp: String = "1970-01-01T00:00:01.000Z",
                  expected: String? = nil) throws -> GeminiHook? {
            let data = try JSONSerialization.data(withJSONObject: ["session_id": chat, "hook_event_name": event,
                "timestamp": stamp, "notification_type": type, "prompt": "private fixture"])
            return GeminiHook.projectCLI(data, event: expected ?? event)
        }
        let permission = try #require(try hook("Notification"))
        let ended = try #require(try hook("AfterAgent", stamp: "1970-01-01T00:00:02Z"))
        #expect(permission.id == ended.id && permission.id != chat)
        #expect(try hook("Notification", expected: "AfterAgent") == nil)
        #expect(try hook("Notification", type: "Other") == nil)
        #expect(try hook("Notification", stamp: "invalid") == nil)
        for malformed in ["1970-01-01T00:00:01.000Zinvalid", "2026-02-30T12:00:00Z",
                          "1970-01-01T00:00:01Z\n", "1970-01-01T00:00:01+00:60"] {
            #expect(try hook("Notification", stamp: malformed) == nil)
        }
        #expect(try hook("Notification", stamp: "1970-01-01T01:00:01.000+01:00") == permission)
        let store = MonitorStore()
        func update(_ events: [GeminiHook], _ ms: Double) -> [String] {
            store.updateGemini(events, at: MonitorTime(wallMS: ms, continuousMS: ms))
        }
        #expect(update([permission], 1001).count == 1)
        #expect(store.attentionCount == 1)
        #expect(update([permission], 1002).isEmpty)
        #expect(update([ended], 2001).isEmpty)
        #expect(store.sessions.first?.state == .turnEnded)
        #expect(update([permission], 33000).isEmpty)
        #expect(store.sessions.first?.state == .unknown)
    }

    @MainActor @Test func sameTimestampConflictStaysUnknownUntilNewEvidence() {
        let id = "cli-" + String(repeating: "a", count: 32)
        let request = GeminiHook(id: id, state: .needsAttention, observed: 1000)
        let ended = GeminiHook(id: id, state: .turnEnded, observed: 1000)
        let newer = GeminiHook(id: id, state: .needsAttention, observed: 1001)
        let now = MonitorTime(wallMS: 1002, continuousMS: 1002)
        for order in [[request, ended], [ended, request]] {
            for split in [false, true] {
                let store = MonitorStore()
                if split { store.updateGemini([order[0]], at: now) }
                #expect(store.updateGemini(split ? [order[1]] : order, at: now).isEmpty)
                #expect(store.sessions.first?.state == .unknown)
                #expect(store.updateGemini([request, ended], at: now).isEmpty)
                #expect(store.sessions.first?.state == .unknown)
                #expect(store.updateGemini([newer], at: now).count == 1)
                #expect(store.sessions.first?.state == .needsAttention)
            }
        }
    }

    @Test func largeCLIFrameRetainsOnlyMetadataAndHonorsLimit() throws {
        var frame = try JSONSerialization.data(withJSONObject: ["session_id": chat, "hook_event_name": "AfterAgent",
            "timestamp": "2026-11-16T00:00:00.123Z", "prompt_response": String(repeating: "x", count: 160_000)])
        frame.append(Data(repeating: 0x20, count: GeminiHook.cliFrameLimit - frame.count))
        let event = try #require(GeminiHook.projectCLI(frame, event: "AfterAgent"))
        #expect(event.state == .turnEnded)
        #expect(try JSONEncoder().encode(event).count < 512)
        #expect(throws: (any Error).self) { try StrictJSON.object(frame) }
        frame.append(0x20)
        #expect(GeminiHook.projectCLI(frame, event: "AfterAgent") == nil)
    }

    @Test func workspaceSetupPreservesUserFiles() throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let config = try GeminiWorkspaceHooks(workspace: workspace, executable: URL(fileURLWithPath: "/Applications/Pulse's App"))
        #expect(try config.status() == .available)
        try config.install()
        #expect(try config.status() == .installed)
        #expect(throws: (any Error).self) { try config.install() }
        try config.remove()
        let file = workspace.appendingPathComponent(".agents/hooks.json")
        try Data("custom".utf8).write(to: file)
        #expect(try config.status() == .occupied)
        #expect(throws: (any Error).self) { try config.remove() }
        #expect(try String(contentsOf: file, encoding: .utf8) == "custom")
    }
}
